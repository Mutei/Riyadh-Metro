import 'nearest_station.dart';

class InterchangePair {
  final NearestStation a; // on origin line
  final NearestStation b; // on destination line
  const InterchangePair({required this.a, required this.b});
}
