// lib/services/places_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../private.dart';

class PlaceSuggestion {
  final String placeId;
  final String title;
  final String subtitle;
  PlaceSuggestion(this.placeId, this.title, this.subtitle);
}

class PlacesService {
  final _uuid = const Uuid();
  String? _sessionToken;

  /// Begin (or reuse) a session for cheaper billing + better results.
  void startSession() => _sessionToken ??= _uuid.v4();

  /// End session after a selection to avoid “stale” bias.
  void endSession() => _sessionToken = null;

  Future<List<PlaceSuggestion>> autocomplete({
    required String input,
    required LatLng biasCenter,
    int radiusMeters = 20000,
    String country = 'sa',
    String language = 'ar',
  }) async {
    if (input.trim().isEmpty) return [];
    startSession();

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=${Uri.encodeComponent(input)}'
      '&key=$kDirectionsApiKey'
      '&language=$language'
      '&components=country:$country'
      '&location=${biasCenter.latitude},${biasCenter.longitude}'
      '&radius=$radiusMeters'
      '&sessiontoken=$_sessionToken',
    );

    final res = await http.get(url);
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body);
    if (data['status'] != 'OK') return [];
    final list = (data['predictions'] as List).take(8).map((p) {
      return PlaceSuggestion(
        p['place_id'] as String,
        p['structured_formatting']?['main_text'] ?? p['description'],
        p['description'] as String,
      );
    }).toList();
    return list;
  }

  Future<LatLng?> detailsLatLng({
    required String placeId,
    String language = 'ar',
  }) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=$placeId'
      '&fields=geometry'
      '&language=$language'
      '&key=$kDirectionsApiKey'
      '&sessiontoken=${_sessionToken ?? _uuid.v4()}',
    );
    final res = await http.get(url);
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    if (data['status'] != 'OK') return null;
    final loc = data['result']['geometry']['location'];
    return LatLng(
      (loc['lat'] as num).toDouble(),
      (loc['lng'] as num).toDouble(),
    );
  }

  /// Text search fallback (good for brands like “Burger King”)
  Future<({LatLng? latLng, String? label})> textSearchFirst({
    required String query,
    required LatLng near,
    int radiusMeters = 20000,
    String region = 'sa',
    String language = 'ar',
  }) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/textsearch/json'
      '?query=${Uri.encodeComponent(query)}'
      '&location=${near.latitude},${near.longitude}'
      '&radius=$radiusMeters'
      '&region=$region'
      '&language=$language'
      '&key=$kDirectionsApiKey',
    );
    final res = await http.get(url);
    if (res.statusCode != 200) return (latLng: null, label: null);
    final data = jsonDecode(res.body);
    final results = (data['results'] as List);
    if (results.isEmpty) return (latLng: null, label: null);
    final first = results.first;
    final geo = first['geometry']['location'];
    return (
      latLng: LatLng(
        (geo['lat'] as num).toDouble(),
        (geo['lng'] as num).toDouble(),
      ),
      label: first['name'] as String?
    );
  }

  /// Reverse geocode a LatLng to a human-readable address (e.g., "8224 Al Masil, Riyadh").
  /// Returns `null` if nothing found or on error.
  Future<String?> reverseGeocode(
    LatLng ll, {
    String language = 'ar', // use 'en' if you want English
  }) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
      '?latlng=${ll.latitude},${ll.longitude}'
      '&language=$language'
      '&key=$kDirectionsApiKey',
    );

    final res = await http.get(url);
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body);
    final status = data['status'] as String?;
    if (status != 'OK') return null;

    final results = (data['results'] as List);
    if (results.isEmpty) return null;

    // First result is usually the most specific (street address / plus code).
    final formatted = results.first['formatted_address'] as String?;
    return (formatted != null && formatted.trim().isNotEmpty)
        ? formatted.trim()
        : null;
  }
}
