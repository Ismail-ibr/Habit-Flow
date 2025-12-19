import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tp6/services/local_storage_service.dart';
import 'package:tp6/services/firestore_services.dart';
import 'package:tp6/models/habit.dart';

class SyncService {
  final LocalStorageService _local = LocalStorageService();
  final FirestoreService _firestore = FirestoreService();
  late StreamSubscription<List<ConnectivityResult>> _sub;

  void start() {
    _sub = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      if (results.every((r) => r == ConnectivityResult.none)) return;
      // first upload any pending local changes
      await _syncPendingHabits();
      // then pull remote changes and merge into local store
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _pullRemoteHabitsForUser(user.uid);
      }
    });
    // initial check
    Connectivity().checkConnectivity().then((
      List<ConnectivityResult> result,
    ) async {
      if (result.every((r) => r == ConnectivityResult.none)) return;
      await _syncPendingHabits();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _pullRemoteHabitsForUser(user.uid);
      }
    });
  }

  /// Pull habits for [userId] from Firestore and merge them into local Hive storage.
  Future<void> _pullRemoteHabitsForUser(String userId) async {
    try {
      final docs = await _firestore.getAllHabitsForUser(userId);

      // Save/overwrite all remote habits locally (Firebase is authoritative)
      final Set<String> remoteIds = <String>{};
      for (final d in docs) {
        final data = d.data() as Map<String, dynamic>;
        data['id'] = data['id'] ?? d.id;
        final remote = Habit.fromMap(data);
        remoteIds.add(remote.id);
        final toSave = Habit(
          id: remote.id,
          userId: remote.userId,
          title: remote.title,
          category: remote.category,
          reminderIntervalHours: remote.reminderIntervalHours,
          reminderTime: remote.reminderTime,
          targetChecksPerWeek: remote.targetChecksPerWeek,
          maxChecksPerDay: remote.maxChecksPerDay,
          weekStartDay: remote.weekStartDay,
          createdAt: remote.createdAt,
          checkHistory: remote.checkHistory,
          currentStreak: remote.currentStreak,
          bestStreak: remote.bestStreak,
          archived: remote.archived,
          pending: false,
        );
        await _local.saveHabit(toSave);
      }

      // Remove any local, non-pending habits that no longer exist remotely
      final localAll = await _local.getAllHabits();
      for (final localHabit in localAll) {
        if (!localHabit.pending && !remoteIds.contains(localHabit.id)) {
          await _local.deleteHabit(localHabit.id);
        }
      }
    } catch (e) {
      // ignore errors - will retry on next connectivity change
    }
  }

  /// Public helper to trigger a pull/merge for the currently signed in user.
  Future<void> pullAndMergeForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _pullRemoteHabitsForUser(user.uid);
    }
  }

  Future<void> _syncPendingHabits() async {
    final pending = await _local.getPendingHabits();
    for (final habit in pending) {
      try {
        final existing = await _firestore.getHabitById(habit.id);
        if (existing == null) {
          await _firestore.createHabit(habit);
        } else {
          await _firestore.updateHabit(habit);
        }
        await _local.markSynced(habit.id);
      } catch (e) {
        // ignore and continue - will retry on next connectivity change
      }
    }
  }

  void dispose() {
    _sub.cancel();
  }
}
