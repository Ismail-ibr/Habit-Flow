import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign up with username, email, and password
  Future<UserCredential> signUpWithEmailAndPassword(
    String username,
    String email,
    String password,
  ) async {
    try {
      // Normalize username
      final normalizedUsername = username.trim().toLowerCase();

      // Check if username already exists
      final usernameQuery = await _firestore
          .collection('users')
          .where('username', isEqualTo: normalizedUsername)
          .limit(1)
          .get();

      if (usernameQuery.docs.isNotEmpty) {
        throw Exception('This username is already taken');
      }

      // Create user with email and password
      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );

      // Save user data to Firestore
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'username': normalizedUsername,
        'email': email.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      return userCredential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') {
        throw Exception('The password provided is too weak.');
      } else if (e.code == 'email-already-in-use') {
        throw Exception('The account already exists for that email.');
      } else {
        throw Exception(e.message ?? 'An error occurred during sign up.');
      }
    } catch (e) {
      // Re-throw the exception if it's already been formatted
      if (e.toString().startsWith('Exception:')) {
        rethrow;
      }
      throw Exception(e.toString());
    }
  }

  /// Sign in with username and password
  Future<UserCredential> signInWithUsername(
    String username,
    String password,
  ) async {
    try {
      final normalizedUsername = username.trim().toLowerCase();

      // Query Firestore to get email from username
      final userQuery = await _firestore
          .collection('users')
          .where('username', isEqualTo: normalizedUsername)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        throw Exception('No user found with this username');
      }

      final email = userQuery.docs.first.data()['email'] as String;

      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        throw Exception('Invalid username or password.');
      } else if (e.code == 'too-many-requests') {
        throw Exception(
          'Too many failed login attempts. Please try again later.',
        );
      } else {
        throw Exception(e.message ?? 'An error occurred during sign in.');
      }
    } catch (e) {
      // Re-throw the exception if it's already been formatted
      if (e.toString().startsWith('Exception:')) {
        rethrow;
      }
      throw Exception(e.toString());
    }
  }

  /// Sign in with email and password (legacy support)
  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        throw Exception('No user found for provided email.');
      } else if (e.code == 'wrong-password') {
        throw Exception('Wrong password provided for that user.');
      } else {
        throw Exception(e.message ?? 'An error occurred during sign in.');
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  /// Get username for current user
  Future<String?> getCurrentUsername() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final doc = await _firestore.collection('users').doc(user.uid).get();

      if (doc.exists) {
        return doc.data()?['username'] as String?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get username by user ID
  Future<String?> getUsernameByUid(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();

      if (doc.exists) {
        return doc.data()?['username'] as String?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Check if username is available
  Future<bool> isUsernameAvailable(String username) async {
    try {
      final normalizedUsername = username.trim().toLowerCase();

      final query = await _firestore
          .collection('users')
          .where('username', isEqualTo: normalizedUsername)
          .limit(1)
          .get();

      return query.docs.isEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Update username
  Future<void> updateUsername(String newUsername) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      final normalizedUsername = newUsername.trim().toLowerCase();

      // Check if username is available
      final isAvailable = await isUsernameAvailable(normalizedUsername);
      if (!isAvailable) {
        throw Exception('This username is already taken');
      }

      await _firestore.collection('users').doc(user.uid).update({
        'username': normalizedUsername,
      });
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  /// Get user data
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Delete account
  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      // Delete user data from Firestore
      await _firestore.collection('users').doc(user.uid).delete();

      // Delete user from Firebase Auth
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw Exception(
          'Please log out and log back in before deleting your account.',
        );
      } else {
        throw Exception(e.message ?? 'Failed to delete account');
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  /// Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        throw Exception('No user found with this email.');
      } else {
        throw Exception(e.message ?? 'Failed to send reset email');
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }
}
