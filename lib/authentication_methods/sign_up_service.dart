import 'dart:math';
import 'package:darb/authentication_methods/sign_up_method.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class SignUpService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Future<UserCredential> signUpAndSave({
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String username,
    required String email,
    required String password,
    String? gender,
    DateTime? dateOfBirth,
  }) async {
    // 1) Create Auth user first (authoritative email uniqueness)
    late UserCredential cred;
    try {
      cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw FirebaseAuthException(
          code: 'email-already-in-use',
          message: 'This email is already in use.',
        );
      }
      rethrow;
    }

    final uid = cred.user!.uid;

    // Raw values (stored in the profile)
    final uname = username.trim();
    final unameLower = uname.toLowerCase();
    final emailLowerRaw = email.trim().toLowerCase();

    // Sanitized keys for index paths (Firebase key-safe)
    final unameKey = _safeKey(unameLower); // username may contain '.'
    final emailKey = _safeKey(emailLowerRaw); // emails contain '.'

    // 2) Claim uniqueness via transactions on index nodes
    final claimed = <DatabaseReference>[];
    try {
      await _claimIndex(
        _db.child('App/Index/UsernameLower/$unameKey'),
        uid,
        onTaken: () => throw FirebaseAuthException(
          code: 'username-already-in-use',
          message: 'This username is already taken.',
        ),
      );
      claimed.add(_db.child('App/Index/UsernameLower/$unameKey'));

      await _claimIndex(
        _db.child('App/Index/PhoneNumber/$phoneNumber'),
        uid,
        onTaken: () => throw FirebaseAuthException(
          code: 'phone-already-in-use',
          message: 'This phone number is already in use.',
        ),
      );
      claimed.add(_db.child('App/Index/PhoneNumber/$phoneNumber'));

      await _claimIndex(
        _db.child('App/Index/EmailLower/$emailKey'),
        uid,
        onTaken: () => throw FirebaseAuthException(
          code: 'email-already-in-use',
          message: 'This email is already in use.',
        ),
      );
      claimed.add(_db.child('App/Index/EmailLower/$emailKey'));
    } catch (e) {
      // Roll back any claimed indices and delete the auth user
      for (final ref in claimed) {
        try {
          await ref.remove();
        } catch (_) {}
      }
      try {
        await cred.user?.delete();
      } catch (_) {}
      rethrow;
    }

    // 3) Allocate customerId and serialNumber
    final customerId = await _nextCustomerId(); // 20259, 20260, ...
    final serialNumber = _generateSerialNumber(); // SN-YYYYMMDDhhmmss-1234

    // 4) Build model (password NOT stored in DB)
    final model = SignUpMethod(
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      phoneNumber: phoneNumber.trim(),
      username: uname,
      email: email.trim(),
      password: password,
      gender: gender,
      dateOfBirth: dateOfBirth,
      userId: uid,
      customerId: customerId,
      serialNumber: serialNumber,
    );

    // 5) Save profile under App/User/<uid>/...
    await _db.child('App/User/$uid').set(model.toJson());

    // 6) Send verification email
    await cred.user!.sendEmailVerification();

    return cred;
  }

  // ---- Helpers ----

  // Claim an index node once; abort if already taken.
  Future<void> _claimIndex(
    DatabaseReference ref,
    String uid, {
    required void Function() onTaken,
  }) async {
    final tx = await ref.runTransaction((current) {
      if (current == null) return Transaction.success(uid);
      return Transaction.abort();
    });
    if (!tx.committed) onTaken();
  }

  Future<int> _nextCustomerId() async {
    final ref = _db.child('App/Meta/LastCustomerId');
    final tx = await ref.runTransaction((current) {
      // Initialize to 20258 so the first assigned is 20259
      final last = (current is int) ? current : 20258;
      return Transaction.success(last + 1);
    });
    if (!tx.committed) {
      throw FirebaseAuthException(
        code: 'customerid-failed',
        message: 'Could not allocate a customer ID. Please try again.',
      );
    }
    return tx.snapshot.value as int;
  }

  String _generateSerialNumber() {
    final now = DateTime.now();
    final ts =
        '${now.year}${_two(now.month)}${_two(now.day)}${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    final rnd = Random().nextInt(9000) + 1000; // 4 digits
    return 'SN-$ts-$rnd';
  }

  // Replace forbidden Firebase key chars . # $ [ ] with underscores
  String _safeKey(String input) => input.replaceAll(RegExp(r'[.#$\[\]]'), '_');

  String _two(int n) => n.toString().padLeft(2, '0');
}
