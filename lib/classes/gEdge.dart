class GEdge {
  final String to;
  final double seconds; // edge weight for shortest path
  final String kind; // 'metro' | 'walk' | 'transfer' | 'src' | 'dst'
  final String? lineKey; // for metro edges
  final double? meters; // for walk/transfer edges
  GEdge({
    required this.to,
    required this.seconds,
    required this.kind,
    this.lineKey,
    this.meters,
  });
}
