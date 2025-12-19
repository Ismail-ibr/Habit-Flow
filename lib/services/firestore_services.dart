import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tp6/models/habit.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> createUser(String uid, Map<String, dynamic> userData) async {
    await _db.collection('users').doc(uid).set(userData);
  }

  Future<DocumentSnapshot> getUser(String uid) async {
    return await _db.collection('users').doc(uid).get();
  }

  Future<void> updateUser(String uid, Map<String, dynamic> userData) async {
    await _db.collection('users').doc(uid).update(userData);
  }

  Future<void> deleteUser(String uid) async {
    await _db.collection('users').doc(uid).delete();
  }

  Future<List<DocumentSnapshot>> getAllUsers() async {
    QuerySnapshot querySnapshot = await _db.collection('users').get();
    return querySnapshot.docs;
  }

  String uid() {
    return _db.collection('users').doc().id;
  }

  // Habit related CRUD operations
  Future<void> createHabit(Habit habit) async {
    await _db.collection('habits').doc(habit.id).set(habit.toMap());
  }

  Future<void> updateHabit(Habit habit) async {
    await _db.collection('habits').doc(habit.id).update(habit.toMap());
  }

  Future<void> deleteHabit(String id) async {
    await _db.collection('habits').doc(id).delete();
  }

  Future<List<DocumentSnapshot>> getAllHabitsForUser(String userId) async {
    QuerySnapshot querySnapshot = await _db
        .collection('habits')
        .where('userId', isEqualTo: userId)
        .get();
    return querySnapshot.docs;
  }

  Future<void> markHabitChecked(
    String id,
    DateTime checkedAt,
    int streak,
    int? maxStreak,
  ) async {
    final updateMap = {
      'lastChecked': checkedAt.millisecondsSinceEpoch,
      'streak': streak,
    };
    if (maxStreak != null) updateMap['maxStreak'] = maxStreak;
    await _db.collection('habits').doc(id).update(updateMap);
  }

  Future<DocumentSnapshot?> getHabitById(String id) async {
    final doc = await _db.collection('habits').doc(id).get();
    return doc.exists ? doc : null;
  }
}
