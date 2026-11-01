import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';

/// Clean, minimal vertical scrolling time selector dialog inspired by the simplicity
/// of the Samsung alarm time selector.
///
/// Features independent scroll wheels for Hours and Minutes with center-highlighted
/// selection windows, haptic feedback, and clear Cancel / Save actions.
class ScrollingTimePickerDialog extends StatefulWidget {
  const ScrollingTimePickerDialog({
    super.key,
    required this.initialTime,
    this.use24HourFormat = false,
  });

  final TimeOfDay initialTime;
  final bool use24HourFormat;

  /// Convenience dialog launcher returning the chosen [TimeOfDay] or `null` if cancelled.
  static Future<TimeOfDay?> show(
    BuildContext context, {
    required TimeOfDay initialTime,
    bool? use24HourFormat,
  }) {
    final mediaQuery = MediaQuery.maybeOf(context);
    final is24Hour =
        use24HourFormat ?? (mediaQuery?.alwaysUse24HourFormat ?? false);

    return showDialog<TimeOfDay>(
      context: context,
      barrierDismissible: true,
      builder: (context) => ScrollingTimePickerDialog(
        initialTime: initialTime,
        use24HourFormat: is24Hour,
      ),
    );
  }

  @override
  State<ScrollingTimePickerDialog> createState() =>
      _ScrollingTimePickerDialogState();
}

class _ScrollingTimePickerDialogState extends State<ScrollingTimePickerDialog> {
  late int _selectedHour; // 0..23 in 24h, or 1..12 in 12h
  late int _selectedMinute; // 0..59
  late bool _isPm; // For 12h mode

  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;
  late final FixedExtentScrollController _periodController;

  static const double _itemHeight = 44.0;
  static const int _loopMultiplier =
      100; // For continuous infinite looping feel

  @override
  void initState() {
    super.initState();
    final hour = widget.initialTime.hour;
    final minute = widget.initialTime.minute;

    _selectedMinute = minute;

    if (widget.use24HourFormat) {
      _selectedHour = hour;
      _isPm = false;
      _hourController = FixedExtentScrollController(
        initialItem: (_loopMultiplier ~/ 2) * 24 + _selectedHour,
      );
      _periodController = FixedExtentScrollController();
    } else {
      _isPm = hour >= 12;
      _selectedHour = hour % 12 == 0 ? 12 : hour % 12;
      _hourController = FixedExtentScrollController(
        initialItem: (_loopMultiplier ~/ 2) * 12 + (_selectedHour - 1),
      );
      _periodController = FixedExtentScrollController(
        initialItem: _isPm ? 1 : 0,
      );
    }

    _minuteController = FixedExtentScrollController(
      initialItem: (_loopMultiplier ~/ 2) * 60 + _selectedMinute,
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _periodController.dispose();
    super.dispose();
  }

  void _onHourChanged(int index) {
    HapticFeedback.selectionClick();
    final int newHour;
    if (widget.use24HourFormat) {
      newHour = index % 24;
    } else {
      newHour = (index % 12) + 1;
    }
    setState(() {
      _selectedHour = newHour;
    });
  }

  void _onMinuteChanged(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedMinute = index % 60;
    });
  }

  void _onPeriodChanged(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _isPm = (index % 2) == 1;
    });
  }

  TimeOfDay _buildSelectedTime() {
    int hour24;
    if (widget.use24HourFormat) {
      hour24 = _selectedHour;
    } else {
      if (_isPm) {
        hour24 = _selectedHour == 12 ? 12 : _selectedHour + 12;
      } else {
        hour24 = _selectedHour == 12 ? 0 : _selectedHour;
      }
    }
    return TimeOfDay(hour: hour24, minute: _selectedMinute);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.dialogRadius,
        side: BorderSide(color: AppColors.border, width: 0.8),
      ),
      contentPadding: const EdgeInsets.fromLTRB(20.0, 24.0, 20.0, 16.0),
      content: SizedBox(
        width: 300.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Set Reminder Time',
                    style: TextStyle(
                      fontSize: 17.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
                Icon(Icons.alarm_rounded, size: 20.0, color: AppColors.accent),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // Time Selector Wheels Container
            Container(
              height: _itemHeight * 5,
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Center selection highlight box
                  Container(
                    height: _itemHeight,
                    margin: const EdgeInsets.symmetric(horizontal: 10.0),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.35),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 4.0,
                          offset: const Offset(0, 1.5),
                        ),
                      ],
                    ),
                  ),

                  // Wheels
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Hours Wheel
                      Expanded(
                        child: Semantics(
                          label:
                              'Scroll to select hour. Currently $_selectedHour',
                          child: ListWheelScrollView.useDelegate(
                            controller: _hourController,
                            itemExtent: _itemHeight,
                            physics: const FixedExtentScrollPhysics(),
                            perspective: 0.003,
                            diameterRatio: 1.5,
                            onSelectedItemChanged: _onHourChanged,
                            childDelegate: ListWheelChildBuilderDelegate(
                              builder: (context, index) {
                                final int hour;
                                if (widget.use24HourFormat) {
                                  hour = index % 24;
                                } else {
                                  hour = (index % 12) + 1;
                                }
                                final isSelected = hour == _selectedHour;
                                return Center(
                                  child: Text(
                                    hour.toString().padLeft(2, '0'),
                                    style: TextStyle(
                                      fontSize: isSelected ? 22.0 : 16.0,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: isSelected
                                          ? AppColors.textPrimary
                                          : AppColors.textMuted,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),

                      // Separator Colon
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.0),
                        child: Text(
                          ':',
                          style: TextStyle(
                            fontSize: 20.0,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),

                      // Minutes Wheel
                      Expanded(
                        child: Semantics(
                          label:
                              'Scroll to select minute. Currently ${_selectedMinute.toString().padLeft(2, '0')}',
                          child: ListWheelScrollView.useDelegate(
                            controller: _minuteController,
                            itemExtent: _itemHeight,
                            physics: const FixedExtentScrollPhysics(),
                            perspective: 0.003,
                            diameterRatio: 1.5,
                            onSelectedItemChanged: _onMinuteChanged,
                            childDelegate: ListWheelChildBuilderDelegate(
                              builder: (context, index) {
                                final minute = index % 60;
                                final isSelected = minute == _selectedMinute;
                                return Center(
                                  child: Text(
                                    minute.toString().padLeft(2, '0'),
                                    style: TextStyle(
                                      fontSize: isSelected ? 22.0 : 16.0,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: isSelected
                                          ? AppColors.textPrimary
                                          : AppColors.textMuted,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),

                      // Period Wheel (AM / PM) if 12-hour format
                      if (!widget.use24HourFormat) ...[
                        const SizedBox(width: 6.0),
                        SizedBox(
                          width: 58.0,
                          child: Semantics(
                            label:
                                'Scroll to select AM or PM. Currently ${_isPm ? "PM" : "AM"}',
                            child: ListWheelScrollView.useDelegate(
                              controller: _periodController,
                              itemExtent: _itemHeight,
                              physics: const FixedExtentScrollPhysics(),
                              perspective: 0.003,
                              diameterRatio: 1.5,
                              onSelectedItemChanged: _onPeriodChanged,
                              childDelegate: ListWheelChildBuilderDelegate(
                                builder: (context, index) {
                                  final isItemPm = (index % 2) == 1;
                                  final isSelected = isItemPm == _isPm;
                                  return Center(
                                    child: Text(
                                      isItemPm ? 'PM' : 'AM',
                                      style: TextStyle(
                                        fontSize: isSelected ? 17.0 : 13.5,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                        color: isSelected
                                            ? AppColors.accent
                                            : AppColors.textMuted,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 12.0,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 10.0,
            ),
          ),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            final time = _buildSelectedTime();
            Navigator.of(context).pop(time);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryButtonBackground,
            foregroundColor: AppColors.primaryButtonForeground,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
              horizontal: 20.0,
              vertical: 10.0,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.0),
            ),
          ),
          child: const Text(
            'Save',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
        ),
      ],
    );
  }
}
