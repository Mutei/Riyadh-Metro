// lib/services/travel_history_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Writes trip sessions to Realtime Database under:
/// App/TravelHistory/<uid>/<entryId>
///
/// For metro trips, we also store:
///  - metroLineKeys: ['Green', 'Yellow', ...]    // ordered line sequence
///  - fromStation:  'First metro station name'
///  - toStation:    'Last metro station name'
class TravelHistoryService {
  final _db = FirebaseDatabase.instance;
  final _auth = FirebaseAuth.instance;

  /// Starts a new trip record and returns its push key (entryId),
  /// or null if no logged-in user is available.
  Future<String?> startTrip({
    required String mode, // 'car' | 'metro'
    required String? originLabel,
    required String? destLabel,
    required LatLng? originLL,
    required LatLng? destLL,

    /// NEW — Only for metro trips (optional, safe to pass nulls for car):
    List<String>? metroLineKeys, // e.g. ['Green', 'Yellow']
    String? fromStation, // e.g. 'King Abdullah Financial District'
    String? toStation, // e.g. 'Al Waha'

    DateTime? startedAt,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    final ref = _db.ref('App/TravelHistory/$uid').push();
    final now = startedAt ?? DateTime.now();

    final entry = <String, dynamic>{
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
    };

    // Attach metro-specific metadata only if provided
    if (metroLineKeys != null && metroLineKeys.isNotEmpty) {
      entry['metroLineKeys'] = metroLineKeys;
    }
    if (fromStation != null && fromStation.isNotEmpty) {
      entry['fromStation'] = fromStation;
    }
    if (toStation != null && toStation.isNotEmpty) {
      entry['toStation'] = toStation;
    }

    await ref.set(entry);
    return ref.key;
  }

  /// Incremental update during an ongoing trip.
  /// Safe to call multiple times (e.g., every ~10s).
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

  /// Finalize the trip with final distance & duration.
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
