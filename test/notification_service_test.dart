import 'package:flutter_test/flutter_test.dart';
import 'package:tp6/services/notification_service.dart';

void main() {
  test(
    'computeNotificationTime returns immediate when one-hour mark passed but due in future',
    () {
      final now = DateTime.now();
      final scheduledAt = now.add(const Duration(minutes: 49)); // 49 min left
      final toSchedule = NotificationService.computeNotificationTime(
        scheduledAt,
        now: now,
      );
      expect(toSchedule, isNotNull);
      expect(toSchedule!.isAfter(now), isTrue);
      expect(toSchedule.difference(now).inSeconds <= 10, isTrue);
    },
  );

  test('computeNotificationTime returns scheduledAt - 1h when in future', () {
    final now = DateTime.now();
    final scheduledAt = now.add(const Duration(hours: 2)); // 2 hours left
    final toSchedule = NotificationService.computeNotificationTime(
      scheduledAt,
      now: now,
    );
    expect(toSchedule, isNotNull);
    expect(toSchedule, scheduledAt.subtract(const Duration(hours: 1)));
  });

  test(
    'computeNotificationTime returns null when scheduledAt already passed',
    () {
      final now = DateTime.now();
      final scheduledAt = now.subtract(const Duration(minutes: 10));
      final toSchedule = NotificationService.computeNotificationTime(
        scheduledAt,
        now: now,
      );
      expect(toSchedule, isNull);
    },
  );
}
