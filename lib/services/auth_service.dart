import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  User? get currentUser => _firebaseAuth.currentUser;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
    } on FirebaseAuthException catch (error) {
      throw AuthServiceException(_messageForCode(error.code));
    }
  }

  Future<void> register({
    required String email,
    required String password,
  }) async {
    try {
      await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
    } on FirebaseAuthException catch (error) {
      throw AuthServiceException(_messageForCode(error.code));
    }
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  String _messageForCode(String code) {
    switch (code) {
      case 'invalid-email':
        return 'The email address format is invalid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists for that email address.';
      case 'weak-password':
        return 'Use a password with at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts detected. Please try again in a moment.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}

class AuthServiceException implements Exception {
  AuthServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
