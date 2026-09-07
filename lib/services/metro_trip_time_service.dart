import '../routing/metro_graph.dart';
import '../classes/gEdge.dart';
import '../classes/station_node.dart';

/// Provides a route-planner estimate when a user has no historical samples.
/// This is deliberately separate from personal trip analytics.
class MetroTripTimeService {
  MetroTripTimeService() : _graph = MetroGraph();

  final MetroGraph _graph;

  MetroRouteTimeEstimate? estimate({
    required String fromStation,
    required String toStation,
  }) =>
      compare(fromStation: fromStation, toStation: toStation)?.fastest;

  /// Returns three transparent route choices over the same metro graph.
  /// They may be identical when the fastest path also has the fewest transfers
  /// and least transfer walking.
  MetroRouteComparison? compare({
    required String fromStation,
    required String toStation,
  }) {
    final from = _normalize(fromStation);
    final to = _normalize(toStation);
    final origins = _graph.stationList
        .where((node) => _normalize(node.name) == from)
        .toList();
    final destinations = _graph.stationList
        .where((node) => _normalize(node.name) == to)
        .toList();
    if (origins.isEmpty || destinations.isEmpty) return null;

    final fastest = _bestRoute(origins, destinations, _RoutePreference.fastest);
    final fewestTransfers =
        _bestRoute(origins, destinations, _RoutePreference.fewestTransfers);
    final leastWalking =
        _bestRoute(origins, destinations, _RoutePreference.leastWalking);
    if (fastest == null || fewestTransfers == null || leastWalking == null) {
      return null;
    }
    return MetroRouteComparison(
      fastest: fastest,
      fewestTransfers: fewestTransfers,
      leastWalking: leastWalking,
    );
  }

  MetroRouteTimeEstimate? _bestRoute(
    Iterable<StationNode> origins,
    Iterable<StationNode> destinations,
    _RoutePreference preference,
  ) {
    MetroRouteTimeEstimate? best;
    for (final origin in origins) {
      for (final destination in destinations) {
        final path = _findPath(origin.id, destination.id, preference);
        if (path == null) continue;
        final candidate = _toEstimate(path);
        if (best == null || _compareEstimate(candidate, best, preference) < 0) {
          best = candidate;
        }
      }
    }
    return best;
  }

  List<GEdge>? _findPath(
    String source,
    String destination,
    _RoutePreference preference,
  ) {
    final pending = <String>{..._graph.baseAdj.keys, source, destination};
    final scores = <String, _RouteScore>{
      for (final node in pending) node: _RouteScore.infinity,
      source: const _RouteScore(),
    };
    final previous = <String, _PreviousStep>{};

    while (pending.isNotEmpty) {
      String? current;
      var bestScore = _RouteScore.infinity;
      for (final node in pending) {
        final score = scores[node] ?? _RouteScore.infinity;
        if (_compareScore(score, bestScore, preference) < 0) {
          current = node;
          bestScore = score;
        }
      }
      if (current == null || bestScore.isInfinite) break;
      pending.remove(current);
      if (current == destination) break;

      for (final edge in _graph.baseAdj[current] ?? const <GEdge>[]) {
        final next = _addEdge(bestScore, edge);
        final existing = scores[edge.to] ?? _RouteScore.infinity;
        if (_compareScore(next, existing, preference) < 0) {
          scores[edge.to] = next;
          previous[edge.to] = _PreviousStep(from: current, edge: edge);
          pending.add(edge.to);
        }
      }
    }

    if ((scores[destination] ?? _RouteScore.infinity).isInfinite) return null;
    final reversed = <GEdge>[];
    var cursor = destination;
    while (cursor != source) {
      final step = previous[cursor];
      if (step == null) return null;
      reversed.add(step.edge);
      cursor = step.from;
    }
    return reversed.reversed.toList(growable: false);
  }

  _RouteScore _addEdge(_RouteScore score, GEdge edge) => _RouteScore(
        seconds: score.seconds + edge.seconds,
        transfers: score.transfers + (edge.kind == 'transfer' ? 1 : 0),
        walkingMeters: score.walkingMeters +
            (edge.kind == 'transfer' || edge.kind == 'walk'
                ? edge.meters ?? 0
                : 0),
      );

  int _compareScore(
    _RouteScore left,
    _RouteScore right,
    _RoutePreference preference,
  ) {
    final leftValues = preference.valuesFor(left);
    final rightValues = preference.valuesFor(right);
    for (var index = 0; index < leftValues.length; index++) {
      final comparison = leftValues[index].compareTo(rightValues[index]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  MetroRouteTimeEstimate _toEstimate(List<GEdge> edges) {
    final score = edges.fold<_RouteScore>(
      const _RouteScore(),
      (total, edge) => _addEdge(total, edge),
    );
    final lines = <String>[];
    for (final edge in edges) {
      final line = edge.lineKey?.trim();
      if (line != null && line.isNotEmpty && !lines.contains(line)) {
        lines.add(line);
      }
    }
    return MetroRouteTimeEstimate(
      seconds: score.seconds.round(),
      lines: lines,
      transfers: score.transfers,
      walkingMeters: score.walkingMeters.round(),
    );
  }

  int _compareEstimate(
    MetroRouteTimeEstimate left,
    MetroRouteTimeEstimate right,
    _RoutePreference preference,
  ) =>
      _compareScore(
        _RouteScore(
          seconds: left.seconds.toDouble(),
          transfers: left.transfers,
          walkingMeters: left.walkingMeters.toDouble(),
        ),
        _RouteScore(
          seconds: right.seconds.toDouble(),
          transfers: right.transfers,
          walkingMeters: right.walkingMeters.toDouble(),
        ),
        preference,
      );

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\b(station|metro)\b'), '')
      .replaceAll('محطة', '')
      .replaceAll(RegExp(r'[^a-z0-9\u0621-\u064A]+'), ' ')
      .trim();
}

class MetroRouteTimeEstimate {
  final int seconds;
  final List<String> lines;
  final int transfers;
  final int walkingMeters;

  const MetroRouteTimeEstimate({
    required this.seconds,
    required this.lines,
    required this.transfers,
    required this.walkingMeters,
  });
}

class MetroRouteComparison {
  final MetroRouteTimeEstimate fastest;
  final MetroRouteTimeEstimate fewestTransfers;
  final MetroRouteTimeEstimate leastWalking;

  const MetroRouteComparison({
    required this.fastest,
    required this.fewestTransfers,
    required this.leastWalking,
  });
}

enum _RoutePreference {
  fastest,
  fewestTransfers,
  leastWalking;

  List<num> valuesFor(_RouteScore score) => switch (this) {
        _RoutePreference.fastest => [
            score.seconds,
            score.transfers,
            score.walkingMeters
          ],
        _RoutePreference.fewestTransfers => [
            score.transfers,
            score.seconds,
            score.walkingMeters
          ],
        _RoutePreference.leastWalking => [
            score.walkingMeters,
            score.transfers,
            score.seconds
          ],
      };
}

class _RouteScore {
  static const infinity = _RouteScore(
    seconds: double.infinity,
    transfers: 1 << 30,
    walkingMeters: double.infinity,
  );

  final double seconds;
  final int transfers;
  final double walkingMeters;

  const _RouteScore({
    this.seconds = 0,
    this.transfers = 0,
    this.walkingMeters = 0,
  });

  bool get isInfinite => seconds.isInfinite;
}

class _PreviousStep {
  final String from;
  final GEdge edge;

  const _PreviousStep({required this.from, required this.edge});
}
