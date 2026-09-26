import 'package:flutter/foundation.dart';

/// Immutable value object representing a normalized calendar date (year, month, day).
///
/// Designed to enforce the "one day = one photo" domain rule by abstracting away
/// exact timestamps, seconds, milliseconds, and time zone offsets, ensuring that
/// photos taken at different hours of the same local day map to the identical key.
@immutable
class DateKey implements Comparable<DateKey> {
  const DateKey(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  /// Creates a [DateKey] from any [DateTime].
  ///
  /// If the provided [dateTime] is UTC, it is converted to the device's local
  /// time zone first so that the key corresponds to the user's local calendar day.
  factory DateKey.fromDateTime(DateTime dateTime) {
    final local = dateTime.isUtc ? dateTime.toLocal() : dateTime;
    return DateKey(local.year, local.month, local.day);
  }

  /// Creates a [DateKey] representing today's date in local time.
  factory DateKey.today() {
    return DateKey.fromDateTime(DateTime.now());
  }

  /// Parses an ISO calendar-date string formatted as 'YYYY-MM-DD'.
  factory DateKey.parse(String isoDate) {
    final parts = isoDate.split('-');
    if (parts.length != 3) {
      throw FormatException(
        'Invalid ISO date string (expected YYYY-MM-DD): $isoDate',
      );
    }
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    return DateKey(year, month, day);
  }

  /// Formats this date as a normalized ISO date string 'YYYY-MM-DD'.
  String format() {
    final y = year.toString().padLeft(4, '0');
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Converts this [DateKey] back to a local [DateTime] at midnight (00:00:00.000).
  DateTime toDateTime({
    int hour = 0,
    int minute = 0,
    int second = 0,
    int millisecond = 0,
  }) {
    return DateTime(year, month, day, hour, minute, second, millisecond);
  }

  /// Checks whether a given [DateTime] falls on the same calendar day.
  bool isSameDay(DateTime other) {
    return this == DateKey.fromDateTime(other);
  }

  /// Whether this [DateKey] represents the user's current local calendar day.
  bool get isToday => this == DateKey.today();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DateKey &&
          runtimeType == other.runtimeType &&
          year == other.year &&
          month == other.month &&
          day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  int compareTo(DateKey other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  String toString() => format();
}
