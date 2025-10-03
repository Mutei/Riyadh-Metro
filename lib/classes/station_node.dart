import 'package:google_maps_flutter/google_maps_flutter.dart';

class StationNode {
  final String id; // "<lineKey>:<index>"
  final String lineKey;
  final int index;
  final String name;
  final LatLng pos;
  StationNode({
    required this.id,
    required this.lineKey,
    required this.index,
    required this.name,
    required this.pos,
  });
}
