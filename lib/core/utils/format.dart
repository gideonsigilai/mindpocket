/// Human formatting helpers. All output is locale-neutral and deterministic so
/// it can be unit tested.
abstract final class Format {
  static String duration(Duration? value) {
    if (value == null || value.inMilliseconds < 0) return '--:--';
    final int totalSeconds = value.inSeconds;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    if (minutes >= 60) {
      final int hours = minutes ~/ 60;
      final int rest = minutes % 60;
      return '$hours:${rest.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static String bytes(int? value) {
    if (value == null || value <= 0) return '0 B';
    const List<String> units = <String>['B', 'KB', 'MB', 'GB'];
    double size = value.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    final String text = size >= 100 || unit == 0
        ? size.toStringAsFixed(0)
        : size.toStringAsFixed(1);
    return '$text ${units[unit]}';
  }

  static String progress(double value) =>
      '${(value.clamp(0, 1) * 100).round()}%';

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// "Today, 14:05", "Yesterday, 09:12", "4 Nov", "4 Nov 2025".
  static String relativeDate(DateTime date, {DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final DateTime local = date.toLocal();
    final DateTime today = DateTime(
      reference.year,
      reference.month,
      reference.day,
    );
    final DateTime day = DateTime(local.year, local.month, local.day);
    final int diff = today.difference(day).inDays;
    final String time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return 'Today, $time';
    if (diff == 1) return 'Yesterday, $time';
    if (local.year == reference.year) {
      return '${local.day} ${_months[local.month - 1]}';
    }
    return '${local.day} ${_months[local.month - 1]} ${local.year}';
  }

  static String shortDate(DateTime date) {
    final DateTime local = date.toLocal();
    return '${local.day} ${_months[local.month - 1]} ${local.year}';
  }
}
