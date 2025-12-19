import 'package:flutter/material.dart';

class Habit {
  String id;
  String userId;
  String title;
  String category;

  // Reminder settings
  int reminderIntervalHours; // How often to remind (e.g., 24 hours)
  TimeOfDay? reminderTime; // What time to send reminder (optional)

  // Target and limits
  int targetChecksPerWeek; // How many times per week to complete
  int maxChecksPerDay; // Maximum checks allowed per day

  // Week start day (0 = Sunday, 1 = Monday, etc.)
  int weekStartDay; // Default: 1 (Monday)

  // Tracking
  DateTime createdAt;
  List<DateTime> checkHistory; // All check timestamps

  // Streaks
  int currentStreak; // Consecutive weeks target was met
  int bestStreak; // Longest streak ever

  bool archived;
  bool pending; // whether needs sync

  Habit({
    required this.id,
    required this.userId,
    required this.title,
    this.category = 'General',
    this.reminderIntervalHours = 24,
    this.reminderTime,
    this.targetChecksPerWeek = 7,
    this.maxChecksPerDay = 1,
    this.weekStartDay = 1, // Monday
    DateTime? createdAt,
    List<DateTime>? checkHistory,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.archived = false,
    this.pending = false,
  }) : createdAt = createdAt ?? DateTime.now(),
       checkHistory = checkHistory ?? [];

  factory Habit.fromMap(Map<String, dynamic> map) {
    return Habit(
      id: map['id'] as String,
      userId: map['userId'] as String,
      title: map['title'] as String,
      category: map['category'] as String? ?? 'General',
      reminderIntervalHours: map['reminderIntervalHours'] as int? ?? 24,
      reminderTime: map['reminderTime'] != null
          ? _timeOfDayFromMinutes(map['reminderTime'] as int)
          : null,
      targetChecksPerWeek: map['targetChecksPerWeek'] as int? ?? 7,
      maxChecksPerDay: map['maxChecksPerDay'] as int? ?? 1,
      weekStartDay: map['weekStartDay'] as int? ?? 1,
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int)
          : DateTime.now(),
      checkHistory:
          (map['checkHistory'] as List<dynamic>?)
              ?.map((e) => DateTime.fromMillisecondsSinceEpoch(e as int))
              .toList() ??
          [],
      currentStreak: map['currentStreak'] as int? ?? 0,
      bestStreak: map['bestStreak'] as int? ?? 0,
      archived: map['archived'] as bool? ?? false,
      pending: map['pending'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'category': category,
      'reminderIntervalHours': reminderIntervalHours,
      'reminderTime': reminderTime != null
          ? _timeOfDayToMinutes(reminderTime!)
          : null,
      'targetChecksPerWeek': targetChecksPerWeek,
      'maxChecksPerDay': maxChecksPerDay,
      'weekStartDay': weekStartDay,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'checkHistory': checkHistory
          .map((e) => e.millisecondsSinceEpoch)
          .toList(),
      'currentStreak': currentStreak,
      'bestStreak': bestStreak,
      'archived': archived,
      'pending': pending,
    };
  }

  static int _timeOfDayToMinutes(TimeOfDay time) {
    return time.hour * 60 + time.minute;
  }

  static TimeOfDay _timeOfDayFromMinutes(int minutes) {
    return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  /// Get the start of the current week based on weekStartDay
  DateTime getWeekStart(DateTime date) {
    final daysSinceWeekStart = (date.weekday - weekStartDay + 7) % 7;
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: daysSinceWeekStart));
  }

  /// Get the end of the current week
  DateTime getWeekEnd(DateTime date) {
    return getWeekStart(date).add(const Duration(days: 7));
  }

  /// Get checks for the current week
  List<DateTime> getChecksThisWeek() {
    final now = DateTime.now();
    final weekStart = getWeekStart(now);
    final weekEnd = getWeekEnd(now);

    return checkHistory.where((check) {
      return check.isAfter(weekStart) && check.isBefore(weekEnd);
    }).toList();
  }

  /// Get checks for today
  List<DateTime> getChecksToday() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    return checkHistory.where((check) {
      return check.isAfter(todayStart) && check.isBefore(todayEnd);
    }).toList();
  }

  /// Check if can add another check today
  bool canCheckToday() {
    return getChecksToday().length < maxChecksPerDay;
  }

  /// Get progress for current week (e.g., "3/7")
  String getWeekProgress() {
    final thisWeek = getChecksThisWeek().length;
    return '$thisWeek/$targetChecksPerWeek';
  }

  /// Check if current week's target is met
  bool isWeekTargetMet() {
    return getChecksThisWeek().length >= targetChecksPerWeek;
  }

  /// Add a check and update streaks
  void addCheck(DateTime checkTime) {
    checkHistory.add(checkTime);
    checkHistory.sort(); // Keep sorted
    pending = true;

    // Update streaks after adding check
    _updateStreaks();
  }

  /// Calculate and update current streak by checking consecutive weeks
  void _updateStreaks() {
    if (checkHistory.isEmpty) {
      currentStreak = 0;
      return;
    }

    final now = DateTime.now();
    final currentWeekStart = getWeekStart(now);

    int streak = 0;
    DateTime checkWeekStart = currentWeekStart;

    // Count backwards from current week
    while (true) {
      final weekEnd = getWeekEnd(checkWeekStart);

      // Count checks in this week
      final checksInWeek = checkHistory.where((check) {
        return check.isAfter(checkWeekStart) && check.isBefore(weekEnd);
      }).length;

      // If target met, increment streak
      if (checksInWeek >= targetChecksPerWeek) {
        streak++;
        // Move to previous week
        checkWeekStart = checkWeekStart.subtract(const Duration(days: 7));
      } else {
        // Streak broken
        break;
      }

      // Safety: don't go back more than 2 years
      if (checkWeekStart.isBefore(now.subtract(const Duration(days: 730)))) {
        break;
      }
    }

    currentStreak = streak;

    // Update best streak
    if (currentStreak > bestStreak) {
      bestStreak = currentStreak;
    }
  }

  /// Force recalculation of streaks (useful after loading from storage)
  void recalculateStreaks() {
    _updateStreaks();
  }

  /// Get next reminder time based on last check and reminder interval
  DateTime? getNextReminderTime() {
    if (checkHistory.isEmpty) {
      // First reminder: use creation time + interval
      final nextReminder = createdAt.add(
        Duration(hours: reminderIntervalHours),
      );

      // If reminderTime is set, adjust to that time of day
      if (reminderTime != null) {
        return _adjustToReminderTime(nextReminder);
      }
      return nextReminder;
    }

    // Get last check time
    final lastCheck = checkHistory.last;
    var nextReminder = lastCheck.add(Duration(hours: reminderIntervalHours));

    // If reminderTime is set, adjust to that time of day
    if (reminderTime != null) {
      nextReminder = _adjustToReminderTime(nextReminder);
    }

    return nextReminder;
  }

  /// Adjust a DateTime to the user's preferred reminder time
  DateTime _adjustToReminderTime(DateTime date) {
    if (reminderTime == null) return date;

    var adjusted = DateTime(
      date.year,
      date.month,
      date.day,
      reminderTime!.hour,
      reminderTime!.minute,
    );

    // If the adjusted time is in the past, move to next day
    if (adjusted.isBefore(DateTime.now())) {
      adjusted = adjusted.add(const Duration(days: 1));
    }

    return adjusted;
  }

  /// Get status for UI display
  HabitStatus getStatus() {
    final checksToday = getChecksToday().length;
    final checksThisWeek = getChecksThisWeek().length;

    if (checksToday >= maxChecksPerDay) {
      return HabitStatus.completedToday;
    } else if (checksThisWeek >= targetChecksPerWeek) {
      return HabitStatus.weeklyTargetMet;
    } else {
      return HabitStatus.available;
    }
  }
}

enum HabitStatus { available, completedToday, weeklyTargetMet }
