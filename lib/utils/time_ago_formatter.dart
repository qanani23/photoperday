/// Utility for formatting relative timestamps into friendly user-facing descriptions.
class TimeAgoFormatter {
  const TimeAgoFormatter._();

  /// Formats a [timestamp] relative to [clock] (defaults to `DateTime.now().toUtc()`).
  ///
  /// Examples:
  /// - < 1 minute ago -> "just now"
  /// - 1 minute ago -> "1 minute ago"
  /// - 5 minutes ago -> "5 minutes ago"
  /// - 1 hour ago -> "1 hour ago"
  /// - 3 hours ago -> "3 hours ago"
  /// - Yesterday -> "yesterday"
  /// - > 2 days ago -> "on M/d"
  static String format(DateTime timestamp, {DateTime? clock}) {
    final now = clock?.toUtc() ?? DateTime.now().toUtc();
    final difference = now.difference(timestamp.toUtc());

    if (difference.isNegative || difference.inSeconds < 60) {
      return 'just now';
    }

    final minutes = difference.inMinutes;
    if (minutes < 60) {
      return '$minutes minute${minutes == 1 ? '' : 's'} ago';
    }

    final hours = difference.inHours;
    if (hours < 24) {
      return '$hours hour${hours == 1 ? '' : 's'} ago';
    }

    final days = difference.inDays;
    if (days == 1) {
      return 'yesterday';
    }
    if (days < 7) {
      return '$days days ago';
    }

    return '${timestamp.month}/${timestamp.day}/${timestamp.year}';
  }
}
