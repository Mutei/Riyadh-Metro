// lib/screens/discover_places_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../widgets/search_field.dart';
import '../localization/language_constants.dart';

class DiscoverPlacesScreen extends StatefulWidget {
  final LatLng? currentLocation;
  final Future<void> Function(LatLng dest, String name) onPickDestination;

  const DiscoverPlacesScreen({
    super.key,
    required this.currentLocation,
    required this.onPickDestination,
  });

  @override
  State<DiscoverPlacesScreen> createState() => _DiscoverPlacesScreenState();
}

class _DiscoverPlacesScreenState extends State<DiscoverPlacesScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  String _query = '';
  String _category = 'All';

  // Simple POI model (proper nouns kept as-is; categories are localized via keys)
  static const _poi = <_Poi>[
    _Poi('Kingdom Centre Tower', 'Landmark', 24.711993479953215,
        46.675375795375196),
    _Poi('Al Faisaliah Mall', 'Landmark', 24.69011239826481, 46.68669185119625),
    _Poi('Boulevard City', 'Entertainment', 24.750602657025937,
        46.613690980033994),
    _Poi('Nakheel Mall', 'Shopping/Cinema', 24.76801117136308,
        46.71496818188384),
    _Poi('The Zone', 'Dining', 24.732146275171363, 46.64927792236184),
    _Poi('Murabba Historic Palace', 'Culture', 24.665700, 46.712700),
    _Poi('Diriyah (At-Turaif)', 'Heritage', 24.737200, 46.575900),
    _Poi('Riyadh Season Zone (varies)', 'Entertainment', 24.774265, 46.738586),
    _Poi('KAFD', 'Business', 24.760572263775725, 46.63951670037443),
    _Poi('Riyadh Park', 'Shopping', 24.756800948274062, 46.62943461071924),
    _Poi('The Boulevard World', 'Dining', 24.77409596801723, 46.59981391071965),
  ];

  List<String> get _categories => [
        'All',
        ...{for (final p in _poi) p.category}
      ];

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered =
        _filterAndSort(_poi, _query, _category, widget.currentLocation);

    return Scaffold(
      appBar: AppBar(
        title: Text(getTranslated(context, 'Discover places')),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SearchField(
              hint: getTranslated(
                  context, 'Search places (e.g., Boulevard, Diriyah)'),
              controller: _queryCtrl,
              onSubmitted: (v) => setState(() => _query = v.trim()),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemBuilder: (_, i) {
                final cat = _categories[i];
                final sel = cat == _category;
                return ChoiceChip(
                  selected: sel,
                  label: Text(getTranslated(context, cat)),
                  onSelected: (_) => setState(() => _category = cat),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: _categories.length,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final p = filtered[i];
                final dist = widget.currentLocation == null
                    ? null
                    : _metersBetween(
                        widget.currentLocation!,
                        LatLng(p.lat, p.lng),
                      );
                return ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.place_outlined),
                  ),
                  title: Text(
                    p.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    dist == null
                        ? getTranslated(context, p.category)
                        : '${getTranslated(context, p.category)} • ${_fmtMeters(dist)} ${getTranslated(context, 'away')}',
                  ),
                  trailing:
                      const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () async {
                    await widget.onPickDestination(
                      LatLng(p.lat, p.lng),
                      p.name,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<_Poi> _filterAndSort(
      List<_Poi> input, String q, String cat, LatLng? here) {
    final ql = q.toLowerCase();
    var list = input.where((p) {
      final matchQ = ql.isEmpty ||
          p.name.toLowerCase().contains(ql) ||
          p.category.toLowerCase().contains(ql);
      final matchC = (cat == 'All') || p.category == cat;
      return matchQ && matchC;
    }).toList();

    if (here != null) {
      list.sort((a, b) {
        final da = _metersBetween(here, LatLng(a.lat, a.lng));
        final db = _metersBetween(here, LatLng(b.lat, b.lng));
        return da.compareTo(db);
      });
    } else {
      list.sort((a, b) => a.name.compareTo(b.name));
    }
    return list;
  }

  // Utilities
  static double _metersBetween(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final la1 = _deg2rad(a.latitude);
    final la2 = _deg2rad(b.latitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return R * c;
  }

  static double _deg2rad(double d) => d * math.pi / 180.0;

  // Instance method so we can localize units
  String _fmtMeters(double m) => m < 1000
      ? '${m.toStringAsFixed(0)} ${getTranslated(context, 'm')}'
      : '${(m / 1000).toStringAsFixed(1)} ${getTranslated(context, 'km')}';
}

class _Poi {
  final String name;
  final String category;
  final double lat;
  final double lng;
  const _Poi(this.name, this.category, this.lat, this.lng);
}
