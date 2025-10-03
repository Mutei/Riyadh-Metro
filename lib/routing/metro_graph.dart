import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../classes/gEdge.dart';
import '../classes/station_node.dart';
import '../classes/dij_result.dart';
import '../classes/node_dist.dart';
import '../latlon/latlong_stations.dart' as metro;
import '../latlon/latlong_stations_directions.dart' as metroPolys;

class MetroGraph {
  // Config
  static const double walkSpeedMps = 1.35;
  static const int metroPerStopSec = 150;
  static const int transferPenaltySec = 60;
  static const double maxTransferMeters = 1200;
  static const double maxOriginDestLinkMeters = 3000;
  static const int originDestCandidates = 5;
  static const double maxDestFromStationMeters = 10000;

  late final Map<String, StationNode> stationMap;
  late final List<StationNode> stationList;
  late final Map<String, List<GEdge>> baseAdj;

  MetroGraph() {
    _buildStationsCache();
    baseAdj = _buildBaseAdjacency();
  }

  // ------- public helpers -------
  double minDistanceToAnyStation(LatLng p) {
    double best = double.infinity;
    for (final n in stationList) {
      final d = _metersBetween(n.pos, p);
      if (d < best) best = d;
    }
    return best;
  }

  List<NodeDist> kNearestStations(LatLng p, int k, double maxMeters) {
    final list = <NodeDist>[];
    for (final n in stationList) {
      final m = _metersBetween(n.pos, p);
      if (m <= maxMeters) list.add(NodeDist(n, m));
    }
    list.sort((a, b) => a.meters.compareTo(b.meters));
    return list.take(k).toList();
  }

  DijResult? dijkstra(String src, String dst, Map<String, List<GEdge>> adj) {
    final dist = <String, double>{};
    final prev = <String, String?>{};
    final prevEdge = <String, GEdge?>{};
    final unvisited = <String>{...adj.keys};

    unvisited.add(src);
    unvisited.add(dst);
    dist.addAll({for (final n in unvisited) n: double.infinity});
    dist[src] = 0;

    while (unvisited.isNotEmpty) {
      String? u;
      double best = double.infinity;
      for (final n in unvisited) {
        final d = dist[n] ?? double.infinity;
        if (d < best) {
          best = d;
          u = n;
        }
      }
      if (u == null) break;
      unvisited.remove(u);
      if (u == dst) break;

      final edges = adj[u];
      if (edges == null) continue;
      for (final e in edges) {
        final v = e.to;
        final alt = (dist[u] ?? double.infinity) + e.seconds;
        if (alt < (dist[v] ?? double.infinity)) {
          dist[v] = alt;
          prev[v] = u;
          prevEdge[v] = e;
          if (!unvisited.contains(v)) unvisited.add(v);
        }
      }
    }

    if ((dist[dst] ?? double.infinity) == double.infinity) return null;

    final path = <String>[];
    final edges = <GEdge>[];
    String? cur = dst;
    while (cur != null) {
      path.add(cur);
      final e = prevEdge[cur];
      if (e != null) edges.add(e);
      cur = prev[cur];
    }
    return DijResult(path.reversed.toList(), edges.reversed.toList());
  }

  // ------- build graph -------
  void _buildStationsCache() {
    final list = <StationNode>[];

    void addLine(String key, List<Map<String, dynamic>> stations) {
      for (int i = 0; i < stations.length; i++) {
        final s = stations[i];
        list.add(StationNode(
          id: '$key:$i',
          lineKey: key,
          index: i,
          name: s['name'] as String,
          pos: LatLng(s['lat'] as double, s['lng'] as double),
        ));
      }
    }

    addLine('blue', metro.blueStations);
    addLine('red', metro.redStations);
    addLine('green', metro.greenStations);
    addLine('purple', metro.purpleStations);
    addLine('yellow', metro.yellowStations);
    addLine('orange', metro.orangeStations);

    stationList = list;
    stationMap = {for (final n in list) n.id: n};
  }

  Map<String, List<GEdge>> _buildBaseAdjacency() {
    final adj = <String, List<GEdge>>{};
    void addEdge(String from, GEdge e) => (adj[from] ??= []).add(e);

    void addLine(String key, int count) {
      for (int i = 0; i < count - 1; i++) {
        final a = '$key:$i';
        final b = '$key:${i + 1}';
        addEdge(
            a,
            GEdge(
                to: b,
                seconds: metroPerStopSec.toDouble(),
                kind: 'metro',
                lineKey: key));
        addEdge(
            b,
            GEdge(
                to: a,
                seconds: metroPerStopSec.toDouble(),
                kind: 'metro',
                lineKey: key));
      }
    }

    addLine('blue', metro.blueStations.length);
    addLine('red', metro.redStations.length);
    addLine('green', metro.greenStations.length);
    addLine('purple', metro.purpleStations.length);
    addLine('yellow', metro.yellowStations.length);
    addLine('orange', metro.orangeStations.length);

    // transfers
    for (final a in stationList) {
      for (final b in stationList) {
        if (a.lineKey == b.lineKey) continue;
        final meters = _metersBetween(a.pos, b.pos);
        if (meters <= maxTransferMeters) {
          final secs = meters / walkSpeedMps + transferPenaltySec;
          addEdge(a.id,
              GEdge(to: b.id, seconds: secs, kind: 'transfer', meters: meters));
        }
      }
    }
    return adj;
  }

  // ------- misc -------
  double _metersBetween(LatLng a, LatLng b) {
    const R = 6371000.0;
    double deg2rad(double d) => d * math.pi / 180.0;
    final dLat = deg2rad(b.latitude - a.latitude);
    final dLon = deg2rad(b.longitude - a.longitude);
    final la1 = deg2rad(a.latitude);
    final la2 = deg2rad(b.latitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }
}
