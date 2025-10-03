import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class LoginService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  /// identifier: email OR username
  /// password: required
  Future<UserCredential> loginWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    if (identifier.trim().isEmpty || password.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-input',
        message: 'Please enter your email/username and password.',
      );
    }

    final isEmail = identifier.contains('@');
    if (isEmail) {
      return _auth.signInWithEmailAndPassword(
        email: identifier.trim(),
        password: password,
      );
    }

    // Username path: App/Index/UsernameLower/<safeKey(usernameLower)> = <uid>
    final unameLower = identifier.trim().toLowerCase();
    final unameKey = _safeKey(unameLower);

    // 1) Get uid from index node
    final uidSnap = await _db.child('App/Index/UsernameLower/$unameKey').get();
    if (!uidSnap.exists) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No account found with that username.',
      );
    }
    final uid = uidSnap.value as String;

    // 2) Fetch the email from the user profile (App/User/<uid>/Email)
    final emailSnap = await _db.child('App/User/$uid/Email').get();
    final email = (emailSnap.value ?? '').toString();
    if (email.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-user-record',
        message: 'Account is missing an email address.',
      );
    }

    // 3) Sign in with resolved email
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // Replace forbidden Firebase key chars . # $ [ ] with underscores
  String _safeKey(String input) => input.replaceAll(RegExp(r'[.#$\[\]]'), '_');
}
