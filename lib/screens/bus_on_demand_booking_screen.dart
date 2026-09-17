import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/colors.dart';
import '../latlon/latlong_stations.dart' as metro;
import '../services/bus_on_demand_service.dart';
import '../services/directions_service.dart';
import '../services/places_service.dart';

class BusOnDemandBookingScreen extends StatefulWidget {
  final BusOnDemandPass pass;

  const BusOnDemandBookingScreen({super.key, required this.pass});

  @override
  State<BusOnDemandBookingScreen> createState() =>
      _BusOnDemandBookingScreenState();
}

class _BusOnDemandBookingScreenState extends State<BusOnDemandBookingScreen> {
  final _directions = DirectionsService();
  BusOnDemandDirection _direction = BusOnDemandDirection.stationToLocation;
  _MetroStationChoice? _station;
  _LocationChoice? _location;
  DateTime? _pickup;
  LegPath? _route;
  bool _loadingRoute = false;
  bool _reviewing = false;
  bool _confirming = false;

  List<_MetroStationChoice> get _stations {
    final byName = <String, _MetroStationChoice>{};
    for (final line in <List<Map<String, dynamic>>>[
      metro.redStations,
      metro.blueStations,
      metro.greenStations,
      metro.orangeStations,
      metro.purpleStations,
      metro.yellowStations,
    ]) {
      for (final raw in line) {
        final name = raw['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        byName.putIfAbsent(
          name.toLowerCase(),
          () => _MetroStationChoice(
            name: name,
            latLng: LatLng(
              (raw['lat'] as num).toDouble(),
              (raw['lng'] as num).toDouble(),
            ),
          ),
        );
      }
    }
    final values = byName.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return values;
  }

  String get _pickupLabel =>
      _direction == BusOnDemandDirection.stationToLocation
          ? (_station?.name ?? 'metro station')
          : (_location?.label ?? 'selected location');

  String get _destinationLabel =>
      _direction == BusOnDemandDirection.stationToLocation
          ? (_location?.label ?? 'selected location')
          : (_station?.name ?? 'metro station');

  String _formatDateTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour < 12 ? 'AM' : 'PM';
    return '${value.day}/${value.month}/${value.year} at $hour:$minute $suffix';
  }

  Future<void> _chooseStation() async {
    final picked = await showModalBottomSheet<_MetroStationChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _StationPicker(stations: _stations),
    );
    if (picked == null || !mounted) return;
    setState(() => _station = picked);
    unawaited(_loadRoutePreview());
  }

  Future<void> _chooseLocation() async {
    final initial = _station?.latLng ?? const LatLng(24.7136, 46.6753);
    final picked = await Navigator.of(context).push<_LocationChoice>(
      MaterialPageRoute(builder: (_) => _BusLocationPicker(initial: initial)),
    );
    if (picked == null || !mounted) return;
    setState(() => _location = picked);
    unawaited(_loadRoutePreview());
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      initialDate:
          _pickup != null && _pickup!.isAfter(first) ? _pickup! : first,
      firstDate: first,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _pickup != null
          ? TimeOfDay.fromDateTime(_pickup!)
          : TimeOfDay.fromDateTime(now.add(const Duration(minutes: 35))),
    );
    if (time == null || !mounted) return;
    final value =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!value.isAfter(now)) {
      _show('Choose a future pickup time.');
      return;
    }
    setState(() => _pickup = value);
  }

  Future<void> _loadRoutePreview() async {
    final station = _station;
    final location = _location;
    if (station == null || location == null) return;
    setState(() {
      _loadingRoute = true;
      _route = null;
    });
    final route = await _directions.routeViaRoads(
      station.latLng,
      location.latLng,
      mode: TravelMode.drive,
    );
    if (!mounted) return;
    setState(() {
      _route = route;
      _loadingRoute = false;
    });
  }

  bool get _ready => _station != null && _location != null && _pickup != null;

  Future<void> _confirm() async {
    final station = _station;
    final location = _location;
    final pickup = _pickup;
    if (station == null || location == null || pickup == null || _confirming)
      return;
    setState(() => _confirming = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Please log in to book Bus on Demand.');
      await BusOnDemandService.createBooking(
        uid: uid,
        booking: BusOnDemandBookingData(
          pass: widget.pass,
          direction: _direction,
          stationName: station.name,
          stationLat: station.latLng.latitude,
          stationLng: station.latLng.longitude,
          locationLabel: location.label,
          locationLat: location.latLng.latitude,
          locationLng: location.latLng.longitude,
          scheduledPickup: pickup,
        ),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Bus on Demand booked'),
          content: Text(
            'Your pickup at $_pickupLabel is booked for ${_formatDateTime(pickup)}. '
            'You will receive reminders starting 30 minutes before arrival.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('View my booking'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on BusOnDemandDuplicateBookingException {
      _show('This Bus on Demand booking already exists.');
    } catch (error) {
      _show('Could not book Bus on Demand: $error');
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_reviewing ? 'Review booking' : 'Bus on Demand'),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _reviewing ? _review(context) : _form(context),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListView(
      key: const ValueKey('booking-form'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        _passHeader(context),
        const SizedBox(height: 24),
        Text('Plan your pickup',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          'Choose whether the Bus on Demand ride connects your metro station to a location or brings you to the station.',
          style: TextStyle(color: cs.onSurface.withOpacity(.7), height: 1.35),
        ),
        const SizedBox(height: 16),
        SegmentedButton<BusOnDemandDirection>(
          segments: const [
            ButtonSegment(
              value: BusOnDemandDirection.stationToLocation,
              icon: Icon(Icons.train_rounded),
              label: Text('Station to location'),
            ),
            ButtonSegment(
              value: BusOnDemandDirection.locationToStation,
              icon: Icon(Icons.location_on_rounded),
              label: Text('Location to station'),
            ),
          ],
          selected: {_direction},
          onSelectionChanged: (value) {
            setState(() => _direction = value.first);
          },
        ),
        const SizedBox(height: 20),
        _selectionTile(
          icon: Icons.train_rounded,
          title: _direction == BusOnDemandDirection.stationToLocation
              ? 'Board at metro station'
              : 'Travel to metro station',
          value: _station?.name,
          placeholder: 'Select metro station',
          onTap: _chooseStation,
        ),
        const SizedBox(height: 12),
        _selectionTile(
          icon: Icons.place_rounded,
          title: _direction == BusOnDemandDirection.stationToLocation
              ? 'Destination location'
              : 'Pickup location',
          value: _location?.label,
          placeholder: 'Search or pin on map',
          onTap: _chooseLocation,
        ),
        const SizedBox(height: 12),
        _selectionTile(
          icon: Icons.schedule_rounded,
          title: 'Scheduled bus arrival',
          value: _pickup == null ? null : _formatDateTime(_pickup!),
          placeholder: 'Choose date and time',
          onTap: _pickDateTime,
        ),
        const SizedBox(height: 16),
        _routePreview(context),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _ready ? () => setState(() => _reviewing = true) : null,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Review booking'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: AppColors.kPrimaryColor,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _review(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListView(
      key: const ValueKey('booking-review'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        _passHeader(context),
        const SizedBox(height: 24),
        Text('Your booking',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        _summaryRow(
            Icons.swap_vert_rounded,
            'Journey',
            _direction == BusOnDemandDirection.stationToLocation
                ? 'Station to location'
                : 'Location to station'),
        _summaryRow(Icons.radio_button_checked_rounded, 'Pickup', _pickupLabel),
        _summaryRow(Icons.flag_rounded, 'Destination', _destinationLabel),
        _summaryRow(Icons.calendar_month_rounded, 'Scheduled pickup',
            _formatDateTime(_pickup!)),
        _summaryRow(
            Icons.confirmation_number_rounded,
            'Metro ticket',
            widget.pass.includesMetro
                ? 'Included for 3 hours after boarding'
                : 'Not included'),
        if (_route != null)
          _summaryRow(Icons.route_rounded, 'Road route',
              '${_distance(_route!.distanceMeters)} · about ${_minutes(_route!.durationSec)}'),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withOpacity(.5),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            'After the driver arrives, open My Tickets and tap “I boarded & activate”. The validity period begins at activation.',
            style: TextStyle(color: cs.onSurface, height: 1.35),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _confirming ? null : _confirm,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: AppColors.kPrimaryColor,
            foregroundColor: Colors.white,
          ),
          child: _confirming
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text('Confirm and book · ${widget.pass.priceSar} SAR'),
        ),
        TextButton(
          onPressed:
              _confirming ? null : () => setState(() => _reviewing = false),
          child: const Text('Edit booking'),
        ),
      ],
    );
  }

  Widget _passHeader(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.kPrimaryColor.withOpacity(.9), cs.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 25,
            backgroundColor: Colors.white24,
            child: Icon(Icons.directions_bus_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.pass.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                    '${widget.pass.priceSar} SAR · ${widget.pass.validity.inMinutes < 60 ? '${widget.pass.validity.inMinutes} minutes' : '${widget.pass.validity.inHours} hours'}',
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectionTile(
      {required IconData icon,
      required String title,
      required String? value,
      required String placeholder,
      required VoidCallback onTap}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withOpacity(.45),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: AppColors.kPrimaryColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface)),
                      const SizedBox(height: 3),
                      Text(value ?? placeholder,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: value == null
                                  ? cs.onSurface.withOpacity(.55)
                                  : cs.onSurface)),
                    ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _routePreview(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_station == null || _location == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(16)),
      child: _loadingRoute
          ? const Row(children: [
              SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Preparing road route...')
            ])
          : _route == null
              ? const Text(
                  'The selected station and location are saved. A road preview is not available right now.',
                )
              : Row(
                  children: [
                    const Icon(Icons.route_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bus route preview',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${_distance(_route!.distanceMeters)} · about ${_minutes(_route!.durationSec)} by road',
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 21, color: AppColors.kPrimaryColor),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(value)
              ])),
        ]),
      );

  String _distance(int meters) =>
      meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '$meters m';
  String _minutes(int seconds) => '${(seconds / 60).ceil()} min';
}

class _StationPicker extends StatefulWidget {
  final List<_MetroStationChoice> stations;
  const _StationPicker({required this.stations});

  @override
  State<_StationPicker> createState() => _StationPickerState();
}

class _StationPickerState extends State<_StationPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.stations
        .where((station) =>
            station.name.toLowerCase().contains(_query.trim().toLowerCase()))
        .toList();
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: Column(children: [
            const SizedBox(height: 12),
            Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4))),
            Padding(
                padding: const EdgeInsets.all(20),
                child: TextField(
                    autofocus: true,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Search metro station'))),
            Expanded(
                child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final station = filtered[index];
                      return ListTile(
                          leading: const Icon(Icons.train_rounded),
                          title: Text(station.name),
                          onTap: () => Navigator.pop(context, station));
                    })),
          ]),
        ),
      ),
    );
  }
}

class _BusLocationPicker extends StatefulWidget {
  final LatLng initial;
  const _BusLocationPicker({required this.initial});

  @override
  State<_BusLocationPicker> createState() => _BusLocationPickerState();
}

class _BusLocationPickerState extends State<_BusLocationPicker> {
  final _places = PlacesService();
  final _search = TextEditingController();
  Timer? _debounce;
  LatLng? _selected;
  String? _label;
  List<PlaceSuggestion> _suggestions = const [];
  bool _lookingUpLabel = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _places.endSession();
    super.dispose();
  }

  void _onQuery(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final result = await _places.autocomplete(
          input: query,
          biasCenter: _selected ?? widget.initial,
          language: 'en');
      if (mounted) setState(() => _suggestions = result);
    });
  }

  Future<void> _setPoint(LatLng point, {String? label}) async {
    setState(() {
      _selected = point;
      _label = label;
      _suggestions = const [];
      _lookingUpLabel = label == null;
    });
    if (label == null) {
      final result = await _places.reverseGeocode(point, language: 'en');
      if (mounted && _selected == point)
        setState(() {
          _label = result ??
              '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
          _lookingUpLabel = false;
        });
    }
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    final point = await _places.detailsLatLng(
        placeId: suggestion.placeId, language: 'en');
    if (point != null) await _setPoint(point, label: suggestion.title);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose location')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition:
                CameraPosition(target: widget.initial, zoom: 13),
            onTap: _setPoint,
            markers: _selected == null
                ? const {}
                : {
                    Marker(
                      markerId: const MarkerId('bus_location'),
                      position: _selected!,
                      infoWindow:
                          InfoWindow(title: _label ?? 'Selected location'),
                    ),
                  },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(14),
                    child: TextField(
                      controller: _search,
                      onChanged: _onQuery,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Search a destination or address',
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                    ),
                  ),
                  if (_suggestions.isNotEmpty)
                    Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(14),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _suggestions.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final item = _suggestions[index];
                            return ListTile(
                              title: Text(item.title),
                              subtitle: Text(
                                item.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _selectSuggestion(item),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: FilledButton.icon(
            onPressed: _selected == null || _lookingUpLabel
                ? null
                : () => Navigator.pop(
                      context,
                      _LocationChoice(label: _label!, latLng: _selected!),
                    ),
            icon: const Icon(Icons.check_rounded),
            label: Text(
              _lookingUpLabel
                  ? 'Naming selected location...'
                  : 'Use this location',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: AppColors.kPrimaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _MetroStationChoice {
  final String name;
  final LatLng latLng;
  const _MetroStationChoice({required this.name, required this.latLng});
}

class _LocationChoice {
  final String label;
  final LatLng latLng;
  const _LocationChoice({required this.label, required this.latLng});
}
