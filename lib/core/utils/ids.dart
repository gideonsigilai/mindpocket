import 'dart:math';

/// URL-safe, timestamped identifiers that sort roughly by creation time.
/// Timestamps are stored separately; this only has to be unique and stable.
abstract final class Ids {
  static final Random _random = Random.secure();

  static String newId([String prefix = '']) {
    final int millis = DateTime.now().millisecondsSinceEpoch;
    final StringBuffer buffer = StringBuffer()..write(millis.toRadixString(36));
    for (int i = 0; i < 8; i++) {
      buffer.write(_random.nextInt(36).toRadixString(36));
    }
    final String id = buffer.toString();
    return prefix.isEmpty ? id : '${prefix}_$id';
  }
}
