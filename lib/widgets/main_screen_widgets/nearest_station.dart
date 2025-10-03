import 'package:google_maps_flutter/google_maps_flutter.dart';

class NearestStation {
  final String? lineKey;
  final int? index;
  final String? name;
  final LatLng? latLng;
  NearestStation({
    required this.lineKey,
    required this.index,
    required this.name,
    required this.latLng,
  });
}
