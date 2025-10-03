import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class TravelHistoryService {
  final _db = FirebaseDatabase.instance;
  final _auth = FirebaseAuth.instance;

  /// Returns the generated entryId (push key) or null if user not logged in.
  Future<String?> startTrip({
    required String mode, // 'car' | 'metro'
    required String? originLabel,
    required String? destLabel,
    required LatLng? originLL,
    required LatLng? destLL,
    DateTime? startedAt,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    final ref = _db.ref('App/TravelHistory/$uid').push();
    final now = startedAt ?? DateTime.now();

    await ref.set({
      'mode': mode,
      'originLabel': originLabel,
      'destLabel': destLabel,
      'originLat': originLL?.latitude,
      'originLng': originLL?.longitude,
      'destLat': destLL?.latitude,
      'destLng': destLL?.longitude,
      'durationSeconds': 0,
      'distanceMeters': 0,
      'startedAt': now.millisecondsSinceEpoch,
      'finishedAt': null,
    });

    return ref.key;
  }

  /// Incremental update (optional). Safe to call multiple times.
  Future<void> updateProgress({
    required String entryId,
    required int distanceMeters,
    required int durationSeconds,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final ref = _db.ref('App/TravelHistory/$uid/$entryId');
    await ref.update({
      'distanceMeters': distanceMeters,
      'durationSeconds': durationSeconds,
    });
  }

  /// Finalize the trip. If the trip was really short, we still write the final numbers.
  Future<void> finishTrip({
    required String entryId,
    required int distanceMeters,
    required int durationSeconds,
    DateTime? finishedAt,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final ref = _db.ref('App/TravelHistory/$uid/$entryId');
    await ref.update({
      'distanceMeters': distanceMeters,
      'durationSeconds': durationSeconds,
      'finishedAt': (finishedAt ?? DateTime.now()).millisecondsSinceEpoch,
    });
  }
}
