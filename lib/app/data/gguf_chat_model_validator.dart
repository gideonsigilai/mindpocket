import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<void> validateStandaloneChatModel(String path) async {
  final file = await File(path).open();
  try {
    final reader = _GgufReader(file, await file.length());
    final magic = await reader.readBytes(4);
    if (magic[0] != 0x47 ||
        magic[1] != 0x47 ||
        magic[2] != 0x55 ||
        magic[3] != 0x46) {
      throw const FormatException('The selected file is not a GGUF model.');
    }

    final version = await reader.readUint32();
    if (version != 2 && version != 3) return;

    final tensorCount = await reader.readCount();
    final metadataCount = await reader.readCount();
    if (tensorCount > 1000000 || metadataCount > 100000) {
      throw const FormatException('The GGUF header contains invalid counts.');
    }

    final metadata = <String, Object?>{};

    for (var index = 0; index < metadataCount; index++) {
      final key = await reader.readString();
      final value = await reader.readMetadataValue(
        await reader.readUint32(),
        retain:
            key == 'general.architecture' ||
            key == 'split.count' ||
            key.endsWith('.block_count') ||
            key.endsWith('.nextn_predict_layers'),
      );
      if (value != null) metadata[key] = value;
    }

    final architecture = metadata['general.architecture'] as String?;
    final blockCount = architecture == null
        ? null
        : metadata['$architecture.block_count'] as int?;
    final draftLayerCount = architecture == null
        ? null
        : metadata['$architecture.nextn_predict_layers'] as int?;
    final splitCount = metadata['split.count'] as int?;

    var hasBaseLayer = false;
    for (var index = 0; index < tensorCount; index++) {
      final name = await reader.readString();
      final dimensions = await reader.readUint32();
      if (dimensions > 8) {
        throw const FormatException('The GGUF tensor table is invalid.');
      }
      await reader.skipBytes(dimensions * 8 + 12);
      if (name.startsWith('blk.0.')) hasBaseLayer = true;
    }

    if (architecture == 'qwen35' &&
        (draftLayerCount ?? 0) > 0 &&
        (blockCount ?? 0) > 1 &&
        (splitCount ?? 1) <= 1 &&
        !hasBaseLayer) {
      throw const FormatException(
        'This Qwen3.5 GGUF contains only speculative draft weights, not the '
        'full model. Load its matching base model to use it for chat.',
      );
    }
  } finally {
    await file.close();
  }
}

class _GgufReader {
  _GgufReader(this.file, this.length);

  final RandomAccessFile file;
  final int length;
  static const _bufferSize = 256 * 1024;
  int _position = 0;
  int _bufferStart = -1;
  Uint8List _buffer = Uint8List(0);

  Future<Uint8List> readBytes(int count) async {
    if (count < 0 || count > length - _position) {
      throw const FormatException('The GGUF file is truncated.');
    }
    if (count > _bufferSize) {
      await file.setPosition(_position);
      final bytes = await file.read(count);
      if (bytes.length != count) {
        throw const FormatException('The GGUF file is truncated.');
      }
      _position += count;
      _bufferStart = -1;
      return bytes;
    }

    await _ensureBuffered(count);
    final offset = _position - _bufferStart;
    final bytes = Uint8List.sublistView(_buffer, offset, offset + count);
    _position += count;
    return bytes;
  }

  Future<void> skipBytes(int count) async {
    if (count < 0 || count > length - _position) {
      throw const FormatException('The GGUF file is truncated.');
    }
    _position += count;
    if (_position > _bufferStart + _buffer.length) _bufferStart = -1;
  }

  Future<int> readUint32() async =>
      ByteData.sublistView(await readBytes(4)).getUint32(0, Endian.little);

  Future<int> readCount() async {
    final value = ByteData.sublistView(await readBytes(8))
        .getUint64(0, Endian.little);
    if (value < 0) {
      throw const FormatException('The GGUF file contains invalid counts.');
    }
    return value;
  }

  Future<String> readString() async {
    final size = await readCount();
    if (size > 16 * 1024 * 1024) {
      throw const FormatException('The GGUF string is too large.');
    }
    try {
      return utf8.decode(await readBytes(size));
    } on FormatException {
      throw const FormatException('The GGUF file contains invalid text.');
    }
  }

  Future<Object?> readMetadataValue(int type, {required bool retain}) async {
    if (type == 8) {
      if (retain) return readString();
      await skipString();
      return null;
    }
    if (type == 9) {
      final itemType = await readUint32();
      final count = await readCount();
      if (count > 10000000) {
        throw const FormatException('The GGUF array is too large.');
      }
      if (itemType == 8) {
        await skipStringArray(count);
      } else {
        final itemSize = _scalarSize(itemType);
        if (count > (length - _position) ~/ itemSize) {
          throw const FormatException('The GGUF file is truncated.');
        }
        await skipBytes(count * itemSize);
      }
      return null;
    }

    final size = _scalarSize(type);
    final bytes = await readBytes(size);
    if (!retain) return null;
    final data = ByteData.sublistView(bytes);
    return switch (type) {
      0 => data.getUint8(0),
      1 => data.getInt8(0),
      2 => data.getUint16(0, Endian.little),
      3 => data.getInt16(0, Endian.little),
      4 => data.getUint32(0, Endian.little),
      5 => data.getInt32(0, Endian.little),
      10 => data.getUint64(0, Endian.little),
      11 => data.getInt64(0, Endian.little),
      _ => null,
    };
  }

  Future<void> skipString() async {
    final size = await readCount();
    await skipBytes(size);
  }

  Future<void> skipStringArray(int count) async {
    for (var index = 0; index < count; index++) {
      if (!_hasBuffered(8)) await _ensureBuffered(8);
      final offset = _position - _bufferStart;
      final size = ByteData.sublistView(_buffer)
          .getUint64(offset, Endian.little);
      if (size < 0 || size > length - _position - 8) {
        throw const FormatException('The GGUF file is truncated.');
      }

      _position += 8;
      if (_hasBuffered(size)) {
        _position += size;
      } else {
        _position += size;
        _bufferStart = -1;
      }
    }
  }

  bool _hasBuffered(int count) {
    final bufferEnd = _bufferStart + _buffer.length;
    return _bufferStart >= 0 &&
        _position >= _bufferStart &&
        _position + count <= bufferEnd;
  }

  Future<void> _ensureBuffered(int count) async {
    if (_hasBuffered(count)) return;

    await file.setPosition(_position);
    _buffer = await file.read(_bufferSize);
    if (_buffer.isEmpty) {
      throw const FormatException('The GGUF file is truncated.');
    }
    _bufferStart = _position;
  }

  int _scalarSize(int type) => switch (type) {
    0 || 1 || 7 => 1,
    2 || 3 => 2,
    4 || 5 || 6 => 4,
    10 || 11 || 12 => 8,
    _ => throw const FormatException(
      'The GGUF file uses an unsupported metadata type.',
    ),
  };
}
