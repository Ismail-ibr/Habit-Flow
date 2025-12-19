import 'package:flutter_test/flutter_test.dart';
import 'package:tp6/models/habit.dart';

void main() {
  test(
    'checkAndResetIfMissed resets streak and updates maxStreak when missed',
    () {
      final h = Habit(
        id: '1',
        userId: 'u',
        title: 'Test',
        periodHours: 24,
        lastChecked: DateTime.now().subtract(const Duration(hours: 25)),
        streak: 5,
        maxStreak: 2,
      );

      final changed = h.checkAndResetIfMissed();

      expect(changed, isTrue);
      expect(h.streak, 0);
      expect(h.maxStreak, 5);
      expect(h.pending, isTrue);
    },
  );

  test('checkAndResetIfMissed does nothing when not missed', () {
    final h = Habit(
      id: '2',
      userId: 'u',
      title: 'Test2',
      periodHours: 24,
      lastChecked: DateTime.now(),
      streak: 3,
      maxStreak: 10,
    );

    final changed = h.checkAndResetIfMissed();

    expect(changed, isFalse);
    expect(h.streak, 3);
    expect(h.maxStreak, 10);
  });
}
