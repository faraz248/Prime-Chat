import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  Stream<User?> get userChanges => _auth.userChanges();

  // Login with Email & Password
  Future<UserCredential> signInWithEmailPassword(String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();

    if (cleanEmail.isEmpty) {
      throw 'Please enter your Gmail address.';
    }
    if (cleanPassword.isEmpty) {
      throw 'Please enter your password.';
    }

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: cleanPassword,
      );

      // Ensure Firestore record is up to date
      await _saveUserToFirestore(credential.user);
      return credential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        throw 'No account found with this Gmail address. Please check your credentials or create a new account.';
      } else if (e.code == 'wrong-password') {
        throw 'Incorrect password. Please verify your password or use Forgot Password.';
      } else if (e.code == 'invalid-credential') {
        // Modern Firebase bundler check: verify with Firestore if user exists
        var query = await _firestore
            .collection('users')
            .where('email', isEqualTo: cleanEmail)
            .limit(1)
            .get();

        if (query.docs.isEmpty && email.trim() != cleanEmail) {
          query = await _firestore
              .collection('users')
              .where('email', isEqualTo: email.trim())
              .limit(1)
              .get();
        }

        if (query.docs.isEmpty) {
          throw 'No account found with this Gmail address. Please check your spelling or sign up.';
        } else {
          throw 'Incorrect password. Please verify your password and try again.';
        }
      } else if (e.code == 'user-disabled') {
        throw 'This account has been suspended by the administrator.';
      } else if (e.code == 'too-many-requests') {
        throw 'Too many failed login attempts. Please wait a few moments and try again.';
      } else if (e.code == 'invalid-email') {
        throw 'Invalid Gmail address format.';
      }
      throw e.message ?? 'Authentication failed. Please try again.';
    } catch (e) {
      if (e is String) rethrow;
      throw 'Sign in error: ${e.toString()}';
    }
  }

  // Register with Email & Password
  Future<UserCredential> signUpWithEmailPassword(String email, String password, String name) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();
    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      throw 'Please enter your full name.';
    }

    // Gmail format check
    if (!cleanEmail.endsWith('@gmail.com')) {
      throw 'Please enter a valid Gmail address (ending in @gmail.com).';
    }

    if (cleanPassword.length < 6) {
      throw 'Password must be at least 6 characters long.';
    }

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: cleanPassword,
      );

      final user = credential.user;
      if (user != null) {
        await user.updateDisplayName(cleanName);

        // Send email verification link so ONLY real inboxes work
        try {
          await user.sendEmailVerification();
        } catch (_) {}

        // Save to Firestore
        await _saveUserToFirestore(user, nameOverride: cleanName);
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw 'This Gmail address is already registered. Please log in instead.';
      } else if (e.code == 'weak-password') {
        throw 'Password is too weak. Please choose a password with at least 6 characters.';
      } else if (e.code == 'invalid-email') {
        throw 'Invalid Gmail address format.';
      }
      throw e.message ?? 'Registration failed. Please try again.';
    } catch (e) {
      if (e is String) rethrow;
      throw 'Sign up error: ${e.toString()}';
    }
  }

  // Sign in directly with device's logged-in Google Account
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return null; // User cancelled
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      await _saveUserToFirestore(
        userCredential.user,
        nameOverride: googleUser.displayName,
      );
      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw e.message ?? 'Google Sign-In failed.';
    } catch (e) {
      throw 'Google Sign-In error: $e';
    }
  }

  // Send Password Reset Link
  Future<void> sendPasswordResetEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) {
      throw 'Please enter your registered Gmail address.';
    }

    // Check if user exists in database
    final query = await _firestore
        .collection('users')
        .where('email', isEqualTo: cleanEmail)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw 'No account found with this Gmail address. Please check your spelling or sign up.';
    }

    try {
      await _auth.sendPasswordResetEmail(email: cleanEmail);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        throw 'No account found with this Gmail address.';
      }
      throw e.message ?? 'Unable to send password reset email. Please try again.';
    } catch (e) {
      if (e is String) rethrow;
      throw 'Error: $e';
    }
  }

  // Resend verification link
  Future<void> resendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  Future<void> _saveUserToFirestore(User? user, {String? nameOverride}) async {
    if (user != null) {
      final userModel = UserModel(
        id: user.uid,
        email: user.email?.toLowerCase() ?? '',
        displayName: nameOverride ?? user.displayName ?? 'User',
        photoUrl: user.photoURL,
      );
      await _firestore.collection('users').doc(user.uid).set(
        userModel.toMap(),
        SetOptions(merge: true),
      );
    }
  }
}
