import 'package:flutter/foundation.dart';

/// Immutable model representing the user's daily reminder configuration.
@immutable
class DailyReminderSettings {
  const DailyReminderSettings({
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  /// Whether the daily photo reminder is active.
  final bool enabled;

  /// The local calendar hour (0..23) to receive the reminder.
  final int hour;

  /// The local calendar minute (0..59) to receive the reminder.
  final int minute;

  /// Default configuration: disabled, 8:00 PM (20:00).
  static const DailyReminderSettings defaultSettings = DailyReminderSettings(
    enabled: false,
    hour: 20,
    minute: 0,
  );

  /// Human-readable 12-hour formatted time (e.g. "8:00 PM", "9:30 AM").
  String get formattedTime {
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    final minuteFormatted = minute.toString().padLeft(2, '0');
    return '$hour12:$minuteFormatted $period';
  }

  /// Converts this model to a JSON map.
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
  };

  /// Creates a [DailyReminderSettings] instance from a JSON map.
  factory DailyReminderSettings.fromJson(Map<String, dynamic> json) {
    return DailyReminderSettings(
      enabled: json['enabled'] as bool? ?? false,
      hour: (json['hour'] as num?)?.toInt() ?? 20,
      minute: (json['minute'] as num?)?.toInt() ?? 0,
    );
  }

  /// Creates a copy with optional updated fields.
  DailyReminderSettings copyWith({bool? enabled, int? hour, int? minute}) {
    return DailyReminderSettings(
      enabled: enabled ?? this.enabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyReminderSettings &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          hour == other.hour &&
          minute == other.minute;

  @override
  int get hashCode => Object.hash(enabled, hour, minute);

  @override
  String toString() =>
      'DailyReminderSettings(enabled: $enabled, time: $formattedTime)';
}
