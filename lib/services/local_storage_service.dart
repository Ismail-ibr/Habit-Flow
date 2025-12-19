import 'package:hive_flutter/hive_flutter.dart';
import 'package:tp6/models/habit.dart';

class LocalStorageService {
  static const String _habitsBox = 'habits';

  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox<Map>(_habitsBox);
    // small settings box used for app preferences
    await Hive.openBox('settings');
  }

  Box<Map> _box() => Hive.box<Map>(_habitsBox);

  Future<List<Habit>> getAllHabits() async {
    final box = _box();
    final list = box.values
        .map((m) => Habit.fromMap(Map<String, dynamic>.from(m)))
        .toList();

    // Recalculate streaks for all habits to ensure accuracy
    for (final h in list) {
      h.recalculateStreaks();
      // Save updated streaks back to storage
      await saveHabit(h);
    }
    return list;
  }

  Future<List<Habit>> getHabitsForUser(String userId) async {
    final box = _box();
    final list = box.values
        .map((m) => Habit.fromMap(Map<String, dynamic>.from(m)))
        .where((h) => h.userId == userId)
        .toList();

    // Recalculate streaks for all habits to ensure accuracy
    for (final h in list) {
      h.recalculateStreaks();
      // Save updated streaks back to storage
      await saveHabit(h);
    }
    return list;
  }

  Future<void> saveHabit(Habit habit) async {
    final box = _box();
    await box.put(habit.id, habit.toMap());
  }

  Future<Habit?> getHabit(String id) async {
    final box = _box();
    final raw = box.get(id);
    if (raw == null) return null;
    final habit = Habit.fromMap(Map<String, dynamic>.from(raw));

    // Recalculate streaks to ensure accuracy
    habit.recalculateStreaks();

    return habit;
  }

  Future<void> deleteHabit(String id) async {
    final box = _box();
    await box.delete(id);
  }

  Future<List<Habit>> getPendingHabits() async {
    final box = _box();
    return box.values
        .map((m) => Habit.fromMap(Map<String, dynamic>.from(m)))
        .where((h) => h.pending)
        .toList();
  }

  Future<void> markSynced(String id) async {
    final box = _box();
    final Map? raw = box.get(id);
    if (raw != null) {
      final map = Map<String, dynamic>.from(raw);
      map['pending'] = false;
      await box.put(id, map);
    }
  }
}
