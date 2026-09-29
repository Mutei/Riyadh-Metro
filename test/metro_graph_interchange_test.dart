import 'package:darb/routing/metro_graph.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ministry of Education uses a bidirectional in-station interchange', () {
    final graph = MetroGraph();
    final greenPlatform = graph.stationList.singleWhere(
      (station) =>
          station.name == 'Ministry of Education' && station.lineKey == 'green',
    );
    final redPlatform = graph.stationList.singleWhere(
      (station) =>
          station.name == 'Ministry of Education' && station.lineKey == 'red',
    );

    final greenToRed = graph.baseAdj[greenPlatform.id]!.singleWhere(
      (edge) => edge.to == redPlatform.id,
    );
    final redToGreen = graph.baseAdj[redPlatform.id]!.singleWhere(
      (edge) => edge.to == greenPlatform.id,
    );

    expect(greenToRed.isInStationTransfer, isTrue);
    expect(redToGreen.isInStationTransfer, isTrue);
    expect(greenToRed.meters, 0);
    expect(redToGreen.meters, 0);
  });

  test('GOSI to every Uthman Bin Affan platform uses in-station transfers', () {
    final graph = MetroGraph();
    final gosi = graph.stationList.singleWhere(
      (station) => station.name == 'GOSI Complex' && station.lineKey == 'green',
    );
    final uthmanPlatforms = graph.stationList.where(
      (station) => station.name == 'Uthman Bin Affan Road',
    );

    for (final uthman in uthmanPlatforms) {
      final route = graph.dijkstra(gosi.id, uthman.id, graph.baseAdj)!;
      final transfers = route.edges.where((edge) => edge.kind == 'transfer');

      expect(transfers, isNotEmpty);
      expect(transfers.every((edge) => edge.isInStationTransfer), isTrue);
    }
  });
}
