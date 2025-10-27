import 'package:firebase_database/firebase_database.dart';

class LineStatus {
  final String id; // 'purple', 'yellow', 'blue', 'red', 'green', 'orange'
  final String state; // e.g., 'normal', 'delay', 'closed'
  final String message; // human text
  final int updatedAt; // epoch ms
  LineStatus(
      {required this.id,
      required this.state,
      required this.message,
      required this.updatedAt});
}

class LineStatusService {
  final DatabaseReference _root = FirebaseDatabase.instance.ref();

  /// Reads a single line status. Case-insensitive key, tolerant to 'Line' vs 'Lines'.
  Future<LineStatus?> getLineStatus(String lineId) async {
    final all = await _readAllInternal();
    if (all.isEmpty) return null;
    final key = lineId.toLowerCase();
    return all[key];
  }

  /// Reads all lines (case-insensitive). Tolerant to both 'Line' and 'Lines' parent keys.
  Future<List<LineStatus>> getAll() async {
    final map = await _readAllInternal();
    return map.values.toList();
  }

  // ---------------- internals ----------------

  Future<Map<String, LineStatus>> _readAllInternal() async {
    // Try both 'Line' and 'Lines' (people often name it differently)
    final candidates = ['App/Status/Line', 'App/Status/Lines'];

    Map<String, LineStatus> result = {};
    for (final path in candidates) {
      final snap = await _root.child(path).get();
      if (!snap.exists) continue;

      // RTDB may return Map<dynamic, dynamic>
      final raw = snap.value;
      if (raw is Map) {
        raw.forEach((k, v) {
          final id = k.toString().toLowerCase(); // case-insensitive
          if (v is Map) {
            final state = (v['state'] ?? '').toString();
            final message = (v['message'] ?? '').toString();
            final updatedAt = _parseEpoch(v['updatedAt']);
            result[id] = LineStatus(
              id: id,
              state: state,
              message: message,
              updatedAt: updatedAt,
            );
          }
        });
      }
    }
    return result;
  }

  int _parseEpoch(Object? x) {
    if (x == null) return 0;
    if (x is int) return x;
    if (x is double) return x.toInt();
    final s = x.toString();
    return int.tryParse(s) ?? 0;
  }
}
