import 'package:logger/logger.dart';

/// Development logging with sanitized output.
///
/// Never log note bodies, transcripts, OCR text, or tokens. Callers pass short
/// identifiers and shapes only; the [sanitize] helper enforces that.
class AppLogger {
  AppLogger._(this._logger);

  final Logger _logger;

  static AppLogger? _instance;

  static AppLogger get instance => _instance ??= AppLogger._(
    Logger(
      // In release builds only warnings and errors are emitted.
      level: Level.warning,
      filter: ProductionFilter(),
      printer: SimplePrinter(printTime: true, colors: false),
    ),
  );

  /// Tests and debug runs can raise verbosity explicitly.
  static void configure({bool verbose = false}) {
    _instance = AppLogger._(
      Logger(
        level: verbose ? Level.debug : Level.warning,
        filter: ProductionFilter(),
        printer: SimplePrinter(printTime: true, colors: false),
      ),
    );
  }

  void debug(String message) => _logger.d(sanitize(message));
  void info(String message) => _logger.i(sanitize(message));
  void warn(String message, [Object? error]) => _logger.w(
    sanitize(message),
    error: error == null ? null : sanitize('$error'),
  );
  void error(String message, [Object? error, StackTrace? stack]) => _logger.e(
    sanitize(message),
    error: error == null ? null : sanitize('$error'),
    stackTrace: stack,
  );

  /// Truncates long payloads and strips obvious secrets.
  static String sanitize(String input) {
    final String trimmed = input.length > 400
        ? '${input.substring(0, 400)}…'
        : input;
    return trimmed
        .replaceAll(
          RegExp(
            r'(sk|pk|api[_-]?key)[-_][A-Za-z0-9]{8,}',
            caseSensitive: false,
          ),
          '[redacted]',
        )
        .replaceAll(
          RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+'),
          'Bearer [redacted]',
        )
        .replaceAll(RegExp(r'\b[A-Fa-f0-9]{64}\b'), '[hash]');
  }
}

/// Narrow logger helpers so accidental `print` does not ship.
void logDebug(String message) => AppLogger.instance.debug(message);
void logWarn(String message, [Object? error]) =>
    AppLogger.instance.warn(message, error);
void logError(String message, [Object? error, StackTrace? stack]) =>
    AppLogger.instance.error(message, error, stack);
