part of 'screenshot_source.dart';

class _ScreenshotDirectory {
  const _ScreenshotDirectory(this.path, {required this.screenshotNamesOnly});

  final String path;
  final bool screenshotNamesOnly;
}

/// Only small metadata pages cross isolates. Directory traversal, fingerprinting
/// and original-file copying never run on the Flutter root isolate.
class _DesktopScreenshotLibrary {
  _DesktopScreenshotLibrary({
    required this.operatingSystem,
    required this.environment,
    this.macCaptureDirectory,
    this.readSystemPreferences = true,
  });

  final String operatingSystem;
  final Map<String, String> environment;
  final String? macCaptureDirectory;
  final bool readSystemPreferences;
  Future<List<_ScreenshotDirectory>>? _discovery;

  Future<List<_ScreenshotDirectory>> _directories() =>
      _discovery ??= _discover();

  Future<List<_ScreenshotDirectory>> _discover() async {
    // Do not capture this object: its cached discovery Future is not sendable.
    final String os = operatingSystem;
    final Map<String, String> env = environment;
    final String? captureDirectory = macCaptureDirectory;
    final bool preferences = readSystemPreferences;
    try {
      return await Isolate.run(
        () => _discoverScreenshotDirectories(
          os,
          env,
          captureDirectory,
          preferences,
        ),
      );
    } catch (_) {
      _discovery = null;
      rethrow;
    }
  }

  Future<bool> hasPermission() async {
    try {
      final List<_ScreenshotDirectory> directories = await _directories();
      return await Isolate.run(() {
        for (final _ScreenshotDirectory directory in directories) {
          _readScreenshotDirectory(directory.path);
        }
        return true;
      });
    } on FileSystemException {
      // Desktop access is filesystem/TCC access, not a mobile storage grant.
      return false;
    }
  }

  Future<int> count() async {
    final List<_ScreenshotDirectory> directories = await _directories();
    final bool windows = operatingSystem == 'windows';
    return Isolate.run(() {
      final Set<String> paths = <String>{};
      _visitScreenshotFiles(directories, windows, (String id, File file) {
        paths.add(id);
      });
      return paths.length;
    });
  }

  Future<List<DeviceScreenshot>> list({
    String? afterId,
    required int limit,
  }) async {
    if (limit <= 0 || limit > 500) {
      throw RangeError.range(limit, 1, 500, 'limit');
    }
    final List<_ScreenshotDirectory> directories = await _directories();
    final bool windows = operatingSystem == 'windows';
    return Isolate.run(() async {
      // Keep at most one bounded page, even for a very large screenshot folder.
      final SplayTreeMap<String, String> page = SplayTreeMap<String, String>();
      _visitScreenshotFiles(directories, windows, (String id, File file) {
        if (afterId != null && id.compareTo(afterId) <= 0) return;
        page[id] = file.path;
        if (page.length > limit) page.remove(page.lastKey());
      });
      final List<DeviceScreenshot> result = <DeviceScreenshot>[];
      for (final MapEntry<String, String> entry in page.entries) {
        final File file = File(entry.value);
        final FileStat before = file.statSync();
        if (before.type != FileSystemEntityType.file) {
          throw FileSystemException(
            'Screenshot disappeared during enumeration.',
            file.path,
          );
        }
        final String digest = before.size <= 25 * 1024 * 1024
            ? (await sha256.bind(file.openRead()).first).toString()
            : 'oversize';
        final FileStat after = file.statSync();
        if (!_sameScreenshotStat(before, after)) {
          throw FileSystemException(
            'Screenshot changed during enumeration.',
            file.path,
          );
        }
        final String name = p.basename(file.path);
        final String revision =
            '${before.modified.microsecondsSinceEpoch}:${before.size}:$digest';
        result.add(
          DeviceScreenshot(
            id: entry.key,
            name: name,
            contentUri: file.uri
                .replace(
                  queryParameters: <String, String>{
                    'modified': '${before.modified.microsecondsSinceEpoch}',
                    'size': '${before.size}',
                    'digest': digest,
                  },
                )
                .toString(),
            takenAt: _screenshotCaptureTime(name) ?? before.modified,
            // Decoding pixels here would cost a full image decode per
            // screenshot; the importer measures dimensions once after copying.
            width: 0,
            height: 0,
            byteSize: before.size,
            bucket: p.basename(p.dirname(file.path)),
            mimeType: _screenshotMimeTypes[p.extension(name).toLowerCase()]!,
            revision: revision,
          ),
        );
      }
      return result;
    });
  }

  Future<void> copyTo(String contentUri, String destination) async {
    final List<_ScreenshotDirectory> directories = await _directories();
    final bool windows = operatingSystem == 'windows';
    await Isolate.run(() async {
      final Uri uri = Uri.parse(contentUri);
      final String? digest = uri.queryParameters['digest'];
      final int? size = int.tryParse(uri.queryParameters['size'] ?? '');
      final int? modified = int.tryParse(uri.queryParameters['modified'] ?? '');
      if (uri.scheme != 'file' ||
          digest == null ||
          size == null ||
          modified == null) {
        throw const FormatException('Invalid desktop screenshot reference.');
      }
      final File source = File.fromUri(uri.replace(query: '', fragment: ''));
      final FileStat before = source.statSync();
      final String canonical = source.resolveSymbolicLinksSync();
      if (FileSystemEntity.typeSync(source.path, followLinks: false) !=
              FileSystemEntityType.file ||
          before.type != FileSystemEntityType.file ||
          before.size != size ||
          before.modified.microsecondsSinceEpoch != modified ||
          !_isAllowedScreenshot(canonical, directories, windows)) {
        throw FileSystemException(
          'Screenshot is no longer readable in its original location.',
          source.path,
        );
      }
      final File output = File(destination);
      if (p.equals(
        p.normalize(p.absolute(source.path)),
        p.normalize(p.absolute(destination)),
      )) {
        throw const FileSystemException(
          'Screenshot staging cannot overwrite the original.',
        );
      }
      final File pending = File(
        '$destination.${DateTime.now().microsecondsSinceEpoch}.pending',
      );
      try {
        source.copySync(pending.path);
        final String copiedDigest =
            (await sha256.bind(pending.openRead()).first).toString();
        if (digest != copiedDigest ||
            !_sameScreenshotStat(before, source.statSync())) {
          throw FileSystemException(
            'Screenshot changed while it was being copied.',
            source.path,
          );
        }
        // Flush the complete original before atomically replacing the staging
        // file. A failed read never publishes a partial import or a receipt.
        final RandomAccessFile handle = pending.openSync(mode: FileMode.append);
        try {
          handle.flushSync();
        } finally {
          handle.closeSync();
        }
        pending.renameSync(output.path);
      } finally {
        if (pending.existsSync()) pending.deleteSync();
      }
    });
  }
}

const Map<String, String> _screenshotMimeTypes = <String, String>{
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.bmp': 'image/bmp',
  '.gif': 'image/gif',
  '.tif': 'image/tiff',
  '.tiff': 'image/tiff',
  '.heic': 'image/heic',
  '.heif': 'image/heif',
};

Future<List<_ScreenshotDirectory>> _discoverScreenshotDirectories(
  String os,
  Map<String, String> environment,
  String? macCaptureDirectory,
  bool readSystemPreferences,
) async {
  final Map<String, String> env = os == 'windows'
      ? <String, String>{
          for (final MapEntry<String, String> entry in environment.entries)
            entry.key.toUpperCase(): entry.value,
        }
      : environment;
  final String? home = env[os == 'windows' ? 'USERPROFILE' : 'HOME'];
  if (home == null || home.isEmpty || !p.isAbsolute(home)) {
    throw const FileSystemException(
      'The user home directory could not be located.',
    );
  }
  final Map<String, _ScreenshotDirectory> roots =
      <String, _ScreenshotDirectory>{};
  void add(String? path, {bool namesOnly = false}) {
    if (path == null || path.isEmpty || !p.isAbsolute(path)) return;
    final String normalized = p.normalize(path);
    // An XDG setting that disables a directory by pointing at HOME must never
    // turn into a scan of all home-directory files.
    if (p.equals(normalized, p.normalize(home))) return;
    final String key = os == 'windows' ? normalized.toLowerCase() : normalized;
    final _ScreenshotDirectory? previous = roots[key];
    roots[key] = _ScreenshotDirectory(
      normalized,
      screenshotNamesOnly: namesOnly && (previous?.screenshotNamesOnly ?? true),
    );
  }

  switch (os) {
    case 'windows':
      final Set<String> pictures = <String>{
        p.join(home, 'Pictures'),
        if (env['PICTURES'] case final String value when p.isAbsolute(value))
          value,
      };
      if (readSystemPreferences) {
        final String? knownPictures = await _readScreenshotPreference(
          'powershell.exe',
          <String>[
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            '[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(); [Environment]::GetFolderPath("MyPictures")',
          ],
        );
        if (knownPictures != null && p.isAbsolute(knownPictures)) {
          pictures.add(knownPictures);
        }
      }
      for (final String key in <String>[
        'ONEDRIVE',
        'ONEDRIVECONSUMER',
        'ONEDRIVECOMMERCIAL',
      ]) {
        final String? drive = env[key];
        if (drive != null && p.isAbsolute(drive)) {
          pictures.add(p.join(drive, 'Pictures'));
        }
      }
      pictures.add(p.join(home, 'OneDrive', 'Pictures'));
      for (final String directory in pictures) {
        add(p.join(directory, 'Screenshots'));
      }
    case 'linux':
      final String configHome =
          env['XDG_CONFIG_HOME'] ?? p.join(home, '.config');
      final Map<String, String> userDirectories = <String, String>{};
      if (p.isAbsolute(configHome)) {
        final File config = File(p.join(configHome, 'user-dirs.dirs'));
        try {
          for (final String line in config.readAsLinesSync()) {
            final RegExpMatch? match = RegExp(
              r'^\s*(XDG_(?:PICTURES|DESKTOP)_DIR)=(.*)$',
            ).firstMatch(line);
            if (match != null) userDirectories[match[1]!] = match[2]!.trim();
          }
        } on FileSystemException catch (error) {
          if (!_missingScreenshotPath(error)) rethrow;
        }
      }
      String xdg(String key, String fallback) =>
          _expandScreenshotDirectory(env[key] ?? userDirectories[key], home) ??
          p.join(home, fallback);
      final String pictures = xdg('XDG_PICTURES_DIR', 'Pictures');
      final String desktop = xdg('XDG_DESKTOP_DIR', 'Desktop');
      add(p.join(pictures, 'Screenshots'));
      add(p.join(pictures, 'screenshots'));
      add(pictures, namesOnly: true);
      add(desktop, namesOnly: true);
    case 'macos':
      String? captureDirectory = macCaptureDirectory;
      if (captureDirectory == null && readSystemPreferences) {
        captureDirectory = await _readScreenshotPreference(
          '/usr/bin/defaults',
          <String>['read', 'com.apple.screencapture', 'location'],
        );
      }
      final String desktop = p.join(home, 'Desktop');
      final String? expanded = _expandScreenshotDirectory(
        captureDirectory,
        home,
      );
      if (expanded != null) {
        add(expanded, namesOnly: !_isDedicatedScreenshotDirectory(expanded));
      }
      add(desktop, namesOnly: true);
      add(p.join(home, 'Pictures', 'Screenshots'));
    default:
      throw UnsupportedError(
        'Screenshot filesystem intake is not available on $os.',
      );
  }
  return roots.values.toList(growable: false);
}

Future<String?> _readScreenshotPreference(
  String executable,
  List<String> arguments,
) async {
  Process? process;
  try {
    process = await Process.start(executable, arguments);
    final Future<String> output = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final Future<void> errors = process.stderr.drain<void>();
    final int code = await process.exitCode.timeout(const Duration(seconds: 5));
    final String value = (await output).trim();
    await errors;
    return code == 0 && value.isNotEmpty ? value : null;
  } on TimeoutException {
    process?.kill();
    return null;
  } on ProcessException {
    // A machine without this optional preference reader still has the standard
    // OS folders; do not invent a path from command errors.
    return null;
  }
}

String? _expandScreenshotDirectory(String? raw, String home) {
  if (raw == null) return null;
  String value = raw.trim();
  if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
    value = value.substring(1, value.length - 1);
  }
  value = value.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
  value = value.replaceAll(r'${HOME}', home).replaceAll(r'$HOME', home);
  if (value.startsWith('~/')) value = p.join(home, value.substring(2));
  if (value.contains(r'$') || value.contains('`')) return null;
  return p.isAbsolute(value) ? p.normalize(value) : null;
}

bool _isDedicatedScreenshotDirectory(String path) => RegExp(
  r'^screen[ _-]?shots?$',
  caseSensitive: false,
).hasMatch(p.basename(path));

bool _isScreenshotName(String name) => RegExp(
  r'^(?:screen[ _-]?shot|screen[ _-]?capture|bildschirmfoto|capture d[’\x27]écran|captura de pantalla)(?:[ _.-]|$)',
  caseSensitive: false,
).hasMatch(name);

bool _missingScreenshotPath(FileSystemException error) =>
    <int>{2, 3}.contains(error.osError?.errorCode);

/// A missing dedicated folder is a valid empty library, but its nearest existing
/// ancestor must really be readable. Access-denied errors are never called empty.
List<FileSystemEntity> _readScreenshotDirectory(String path) {
  if (FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.link) {
    return const <FileSystemEntity>[];
  }
  try {
    return Directory(path).listSync(followLinks: false);
  } on FileSystemException catch (error) {
    if (!_missingScreenshotPath(error)) rethrow;
    String parent = p.dirname(path);
    while (parent != path) {
      try {
        if (FileSystemEntity.typeSync(parent, followLinks: false) ==
            FileSystemEntityType.link) {
          return const <FileSystemEntity>[];
        }
        Directory(parent).listSync(followLinks: false);
        return const <FileSystemEntity>[];
      } on FileSystemException catch (ancestorError) {
        if (!_missingScreenshotPath(ancestorError)) rethrow;
      }
      path = parent;
      parent = p.dirname(parent);
    }
    rethrow;
  }
}

void _visitScreenshotFiles(
  List<_ScreenshotDirectory> directories,
  bool windows,
  void Function(String id, File file) visit,
) {
  final Set<String> visitedDirectories = <String>{};
  for (final _ScreenshotDirectory directory in directories) {
    final List<FileSystemEntity> entries = _readScreenshotDirectory(
      directory.path,
    );
    if (entries.isEmpty) continue;
    final String canonicalDirectory = Directory(directory.path)
        .resolveSymbolicLinksSync();
    final String directoryKey = windows
        ? canonicalDirectory.toLowerCase()
        : canonicalDirectory;
    // A path can appear both in a redirected standard folder and in OneDrive.
    final String classificationKey =
        '$directoryKey:${directory.screenshotNamesOnly}';
    if (!visitedDirectories.add(classificationKey)) continue;
    for (final FileSystemEntity entity in entries) {
      if (entity is! File ||
          FileSystemEntity.typeSync(entity.path, followLinks: false) !=
              FileSystemEntityType.file) {
        continue;
      }
      final String name = p.basename(entity.path);
      if (!_screenshotMimeTypes.containsKey(p.extension(name).toLowerCase()) ||
          (directory.screenshotNamesOnly && !_isScreenshotName(name))) {
        continue;
      }
      final String canonical = entity.resolveSymbolicLinksSync();
      if (!p.equals(p.dirname(canonical), canonicalDirectory)) continue;
      final File file = File(canonical);
      final String id = windows
          ? file.uri.toString().toLowerCase()
          : file.uri.toString();
      visit(id, file);
    }
  }
}

bool _isAllowedScreenshot(
  String canonical,
  List<_ScreenshotDirectory> directories,
  bool windows,
) {
  final String parent = p.dirname(canonical);
  final String name = p.basename(canonical);
  if (!_screenshotMimeTypes.containsKey(p.extension(name).toLowerCase())) {
    return false;
  }
  for (final _ScreenshotDirectory directory in directories) {
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      continue;
    }
    final String root = Directory(directory.path).resolveSymbolicLinksSync();
    final bool same = windows
        ? parent.toLowerCase() == root.toLowerCase()
        : p.equals(parent, root);
    if (same && (!directory.screenshotNamesOnly || _isScreenshotName(name))) {
      return true;
    }
  }
  return false;
}

bool _sameScreenshotStat(FileStat a, FileStat b) =>
    b.type == FileSystemEntityType.file &&
    a.size == b.size &&
    a.modified == b.modified &&
    a.changed == b.changed;

DateTime? _screenshotCaptureTime(String name) {
  final RegExpMatch? match = RegExp(
    r'(\d{4})[-_](\d{2})[-_](\d{2})[ _]+(?:at[ _]+)?(\d{1,2})[.:_-](\d{2})[.:_-](\d{2})(?:[ \u202f\u00a0]*(AM|PM))?',
    caseSensitive: false,
  ).firstMatch(name);
  if (match == null) return null;
  final List<int> parts = <int>[
    for (int i = 1; i <= 6; i++) int.parse(match[i]!),
  ];
  final String? period = match[7]?.toUpperCase();
  int hour = parts[3];
  if (period != null) {
    if (hour < 1 || hour > 12) return null;
    hour = hour % 12 + (period == 'PM' ? 12 : 0);
  }
  final DateTime time = DateTime(
    parts[0],
    parts[1],
    parts[2],
    hour,
    parts[4],
    parts[5],
  );
  return time.year == parts[0] &&
          time.month == parts[1] &&
          time.day == parts[2] &&
          time.hour == hour &&
          time.minute == parts[4] &&
          time.second == parts[5]
      ? time
      : null;
}
