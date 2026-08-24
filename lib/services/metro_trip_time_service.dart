import '../routing/metro_graph.dart';

/// Provides a route-planner estimate when a user has no historical samples.
/// This is deliberately separate from personal trip analytics.
class MetroTripTimeService {
  MetroTripTimeService() : _graph = MetroGraph();

  final MetroGraph _graph;

  MetroRouteTimeEstimate? estimate({
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

    MetroRouteTimeEstimate? best;
    for (final origin in origins) {
      for (final destination in destinations) {
        final result =
            _graph.dijkstra(origin.id, destination.id, _graph.baseAdj);
        if (result == null) continue;
        final seconds = result.edges.fold<double>(
          0,
          (total, edge) => total + edge.seconds,
        );
        final lines = <String>[];
        var transfers = 0;
        for (final edge in result.edges) {
          if (edge.kind == 'transfer') transfers++;
          final line = edge.lineKey?.trim();
          if (line != null && line.isNotEmpty && !lines.contains(line)) {
            lines.add(line);
          }
        }
        final estimate = MetroRouteTimeEstimate(
          seconds: seconds.round(),
          lines: lines,
          transfers: transfers,
        );
        if (best == null || estimate.seconds < best.seconds) best = estimate;
      }
    }
    return best;
  }

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

  const MetroRouteTimeEstimate({
    required this.seconds,
    required this.lines,
    required this.transfers,
  });
}
