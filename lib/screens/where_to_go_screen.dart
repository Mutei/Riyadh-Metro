// lib/screens/where_to_go_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class WhereToGoScreen extends StatefulWidget {
  /// Optional: pass the user's current location to compute "nearby" distances.
  final LatLng? currentLocation;

  /// Optional: get the destination back to your map/planner.
  /// If provided, it's called when the user taps a card or CTA.
  final void Function(LatLng dest, String name)? onPickDestination;

  const WhereToGoScreen({
    super.key,
    this.currentLocation,
    this.onPickDestination,
  });

  @override
  State<WhereToGoScreen> createState() => _WhereToGoScreenState();
}

class _WhereToGoScreenState extends State<WhereToGoScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _activeCategory = 'All';

  late final List<_Category> _categories = [
    _Category('All', Icons.all_inclusive_rounded),
    _Category('Landmarks', Icons.apartment_rounded),
    _Category('Shopping', Icons.shopping_bag_rounded),
    _Category('Entertainment', Icons.celebration_rounded),
    _Category('Culture', Icons.museum_rounded),
    _Category('Parks', Icons.park_rounded),
    _Category('Airport', Icons.flight_takeoff_rounded),
  ];

  late final List<_Destination> _all = [
    _Destination(
      name: 'Kingdom Centre Tower',
      summary: 'Sky Bridge views over Riyadh',
      category: 'Landmarks',
      latLng: const LatLng(24.7116, 46.6744),
      tags: const ['Views', 'Iconic'],
    ),
    _Destination(
      name: 'KAFD',
      summary: 'Futuristic business & lifestyle district',
      category: 'Landmarks',
      latLng: const LatLng(24.7636, 46.6361),
      tags: const ['Dining', 'Walkable'],
    ),
    _Destination(
      name: 'Boulevard Riyadh City',
      summary: 'Flagship entertainment & events zone',
      category: 'Entertainment',
      latLng: const LatLng(24.7746, 46.6191),
      tags: const ['Events', 'Dining'],
    ),
    _Destination(
      name: 'Diriyah (At-Turaif)',
      summary: 'UNESCO heritage, mud-brick architecture',
      category: 'Culture',
      latLng: const LatLng(24.7348, 46.5755),
      tags: const ['Heritage', 'Museums'],
    ),
    _Destination(
      name: 'National Museum of Saudi Arabia',
      summary: 'Centuries of Arabian history',
      category: 'Culture',
      latLng: const LatLng(24.6486, 46.7106),
      tags: const ['Museum', 'History'],
    ),
    _Destination(
      name: 'King Abdullah Park',
      summary: 'Lakes, lawns & light shows',
      category: 'Parks',
      latLng: const LatLng(24.6425, 46.7389),
      tags: const ['Family', 'Green'],
    ),
    _Destination(
      name: 'Riyadh Front',
      summary: 'Retail, dining & exhibitions',
      category: 'Shopping',
      latLng: const LatLng(24.9571, 46.7113),
      tags: const ['Shopping', 'Dining'],
    ),
    _Destination(
      name: 'Salam Park',
      summary: 'Palm-lined paths & lake views',
      category: 'Parks',
      latLng: const LatLng(24.6212, 46.7119),
      tags: const ['Family', 'Relax'],
    ),
    _Destination(
      name: 'King Khalid International Airport (RUH)',
      summary: 'Gateway to Riyadh',
      category: 'Airport',
      latLng: const LatLng(24.9578, 46.6988),
      tags: const ['Travel'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final filtered = _all.where((d) {
      final q = _searchCtrl.text.trim().toLowerCase();
      final matchesCategory =
          _activeCategory == 'All' || d.category == _activeCategory;
      final matchesQuery = q.isEmpty ||
          d.name.toLowerCase().contains(q) ||
          d.summary.toLowerCase().contains(q) ||
          d.tags.any((t) => t.toLowerCase().contains(q));
      return matchesCategory && matchesQuery;
    }).toList();

    // Sort a "nearby" list by distance if we know where the user is
    final nearby = [..._all];
    if (widget.currentLocation != null) {
      nearby.sort((a, b) => _metersBetween(widget.currentLocation!, a.latLng)
          .compareTo(_metersBetween(widget.currentLocation!, b.latLng)));
    }

    final featured = [
      _all.firstWhere((d) => d.name.contains('Boulevard')),
      _all.firstWhere((d) => d.name.contains('Diriyah')),
      _all.firstWhere((d) => d.name.contains('Kingdom Centre')),
    ];

    return Scaffold(
      backgroundColor:
          isDark ? theme.colorScheme.surface : const Color(0xFFF6F9F3),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: theme.colorScheme.onSurface,
        centerTitle: false,
        title: const Text('Where can you go?',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          // Search
          _SearchBar(
            controller: _searchCtrl,
            hint: 'Search places, malls, parks...',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),

          // Categories
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = _categories[i];
                final selected = c.name == _activeCategory;
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(c.icon, size: 16),
                      const SizedBox(width: 6),
                      Text(c.name),
                    ],
                  ),
                  selected: selected,
                  onSelected: (_) => setState(() => _activeCategory = c.name),
                  selectedColor: theme.colorScheme.primary.withOpacity(.12),
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                  side: BorderSide(
                    color:
                        selected ? theme.colorScheme.primary : Colors.black12,
                  ),
                  backgroundColor: isDark
                      ? theme.colorScheme.surfaceVariant.withOpacity(.4)
                      : Colors.white,
                );
              },
            ),
          ),
          const SizedBox(height: 18),

          // Featured carousel
          _SectionHeader(title: 'Featured this week', icon: Icons.star_rounded),
          const SizedBox(height: 10),
          SizedBox(
            height: 160,
            child: PageView.builder(
              controller: PageController(viewportFraction: .88),
              itemCount: featured.length,
              itemBuilder: (_, i) => _FeaturedCard(
                destination: featured[i],
                onTap: _handlePick,
              ),
            ),
          ),
          const SizedBox(height: 22),

          // Nearby
          _SectionHeader(
            title: 'Nearby',
            icon: Icons.place_rounded,
            trailing: widget.currentLocation == null
                ? const Text('Enable location for distances',
                    style: TextStyle(fontSize: 12, color: Colors.black54))
                : null,
          ),
          const SizedBox(height: 8),
          ...nearby.take(4).map((d) => _DestinationTile(
                destination: d,
                distanceText: widget.currentLocation == null
                    ? null
                    : _fmtMeters(
                        _metersBetween(widget.currentLocation!, d.latLng)),
                onTap: _handlePick,
              )),
          const SizedBox(height: 22),

          // All results (filtered)
          _SectionHeader(
            title: 'All destinations',
            icon: Icons.explore_rounded,
            trailing: Text('${filtered.length} found',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            _EmptyState(
                message:
                    'No places match your search. Try a different keyword.'),
          ...filtered.map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DestinationCard(
                  destination: d,
                  distanceText: widget.currentLocation == null
                      ? null
                      : _fmtMeters(
                          _metersBetween(widget.currentLocation!, d.latLng)),
                  onPick: _handlePick,
                ),
              )),
        ],
      ),
    );
  }

  void _handlePick(_Destination d) {
    if (widget.onPickDestination != null) {
      widget.onPickDestination!(d.latLng, d.name);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Selected: ${d.name}')),
      );
    }
  }

  // --- Small geo helpers ---
  double _metersBetween(LatLng a, LatLng b) {
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

  double _deg2rad(double d) => d * math.pi / 180.0;

  String _fmtMeters(double m) {
    if (m < 1000) return '${m.toStringAsFixed(0)} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }
}

// ===== UI bits =====

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  const _SearchBar(
      {required this.controller, required this.hint, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        hintText: hint,
        filled: true,
        fillColor: theme.brightness == Brightness.dark
            ? theme.colorScheme.surfaceVariant.withOpacity(.4)
            : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;
  const _SectionHeader(
      {required this.title, required this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  final _Destination destination;
  final void Function(_Destination) onTap;

  const _FeaturedCard({required this.destination, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onTap(destination),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary.withOpacity(.85),
              theme.colorScheme.primaryContainer.withOpacity(.85),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
                blurRadius: 18,
                spreadRadius: -6,
                color: Colors.black.withOpacity(.2))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Positioned(
                right: 0,
                bottom: 0,
                child: Icon(Icons.location_city_rounded,
                    size: 88, color: Colors.white.withOpacity(.15)),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Pill(text: destination.category),
                  const Spacer(),
                  Text(destination.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(destination.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withOpacity(.9))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  final _Destination destination;
  final String? distanceText;
  final void Function(_Destination) onTap;

  const _DestinationTile({
    required this.destination,
    required this.onTap,
    this.distanceText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.brightness == Brightness.dark
          ? theme.colorScheme.surfaceVariant.withOpacity(.35)
          : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: () => onTap(destination),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: theme.colorScheme.primary.withOpacity(.12),
          child: Icon(Icons.place_rounded, color: theme.colorScheme.primary),
        ),
        title: Text(destination.name,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(destination.summary,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (distanceText != null)
              Text(distanceText!,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            _Pill(text: destination.category, dense: true),
          ],
        ),
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  final _Destination destination;
  final String? distanceText;
  final void Function(_Destination) onPick;

  const _DestinationCard({
    required this.destination,
    required this.onPick,
    this.distanceText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? theme.colorScheme.surfaceVariant.withOpacity(.35)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              blurRadius: 16,
              spreadRadius: -8,
              color: Colors.black.withOpacity(.10))
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onPick(destination),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon block
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.explore_rounded,
                    color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              // Texts
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: -6,
                      children: [
                        _Pill(text: destination.category, dense: true),
                        ...destination.tags
                            .take(2)
                            .map((t) => _Pill(text: t, dense: true)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(destination.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(destination.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (distanceText != null) ...[
                          const Icon(Icons.directions_walk_rounded,
                              size: 18, color: Colors.black54),
                          const SizedBox(width: 4),
                          Text(distanceText!,
                              style: const TextStyle(color: Colors.black87)),
                          const SizedBox(width: 12),
                        ],
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => onPick(destination),
                          icon: const Icon(Icons.route_rounded),
                          label: const Text('Route on Metro'),
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.primary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final bool dense;
  const _Pill({required this.text, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10, vertical: dense ? 4 : 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: dense ? 11 : 12,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

// ===== Models =====

class _Category {
  final String name;
  final IconData icon;
  _Category(this.name, this.icon);
}

class _Destination {
  final String name;
  final String summary;
  final String category;
  final LatLng latLng;
  final List<String> tags;

  const _Destination({
    required this.name,
    required this.summary,
    required this.category,
    required this.latLng,
    this.tags = const [],
  });
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: Colors.black26),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
