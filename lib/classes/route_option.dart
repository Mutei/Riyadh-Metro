import 'package:darb/classes/station_node.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'gEdge.dart';

class RouteOption {
  final List<String> nodeIds; // includes 'SRC' ... 'DST'
  final Map<String, StationNode> nodes;
  final List<GEdge> edgesInOrder; // parallel to node pairs
  final double totalSeconds;
  final double walkMeters;
  final int transfers;
  final List<String> lineSequence; // e.g. ["purple","green"]
  final LatLng originLL;
  final LatLng destLL;
  RouteOption({
    required this.nodeIds,
    required this.nodes,
    required this.edgesInOrder,
    required this.totalSeconds,
    required this.walkMeters,
    required this.transfers,
    required this.lineSequence,
    required this.originLL,
    required this.destLL,
  });
}
