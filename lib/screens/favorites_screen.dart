// lib/screens/favorites_screen.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../localization/language_constants.dart';
import '../services/places_service.dart';
import '../widgets/search_field.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _db = FirebaseDatabase.instance;
  final _auth = FirebaseAuth.instance;
  DatabaseReference? _favRef;
  StreamSubscription<DatabaseEvent>? _sub;

  final _places = PlacesService();
  List<FavoritePlace> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      _loading = false;
      return;
    }
    _favRef = _db.ref('App/Favorites/$uid');
    _sub = _favRef!.onValue.listen((event) {
      final data = event.snapshot.value;
      final list = <FavoritePlace>[];
      if (data is Map) {
        data.forEach((key, val) {
          if (val is Map) {
            list.add(
              FavoritePlace.fromMap(
                  key as String, Map<Object?, Object?>.from(val)),
            );
          }
        });
      }
      list.sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      setState(() {
        _items = list;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _addOrEdit({FavoritePlace? existing}) async {
    final res = await showModalBottomSheet<FavoritePlace>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _FavoriteEditor(
        places: _places,
        initial: existing,
      ),
    );

    if (res == null || _favRef == null) return;

    if (existing == null) {
      await _favRef!.push().set(res.toMap());
    } else {
      await _favRef!.child(existing.id).set(res.toMap());
    }
  }

  Future<void> _delete(FavoritePlace item) async {
    if (_favRef == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(getTranslated(context, 'Delete favorite')),
        content: Text(getTranslated(
            context, 'Are you sure you want to delete this favorite?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(getTranslated(context, 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(getTranslated(context, 'Delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _favRef!.child(item.id).remove();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(getTranslated(context, 'Favorite deleted'))),
        );
      }
    }
  }

  IconData _iconForType(String t) {
    switch (t.toLowerCase()) {
      case 'home':
        return Icons.home_rounded;
      case 'work':
        return Icons.work_rounded;
      case 'school':
        return Icons.school_rounded;
      default:
        return Icons.star_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(getTranslated(context, 'Favorites')),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _emptyState(context)
              : ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemBuilder: (_, i) {
                    final f = _items[i];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Icon(_iconForType(f.type)),
                      ),
                      title: Text(
                        f.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        f.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () async {
                        // Quick actions (one returns the item up to the caller)
                        await showModalBottomSheet(
                          context: context,
                          shape: const RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(18)),
                          ),
                          builder: (_) => SafeArea(
                            child: Wrap(children: [
                              ListTile(
                                leading: const Icon(Icons.navigation_rounded),
                                title: Text(getTranslated(
                                    context, 'Use as destination')),
                                onTap: () {
                                  Navigator.of(context).pop(f);
                                  Navigator.of(context).pop(f); // return
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.edit_rounded),
                                title: Text(getTranslated(context, 'Edit')),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  _addOrEdit(existing: f);
                                },
                              ),
                              ListTile(
                                leading:
                                    const Icon(Icons.delete_outline_rounded),
                                title: Text(getTranslated(context, 'Delete')),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  _delete(f);
                                },
                              ),
                            ]),
                          ),
                        );
                      },
                      onLongPress: () => _addOrEdit(existing: f),
                      trailing: IconButton(
                        icon: const Icon(Icons.more_vert_rounded),
                        onPressed: () => _addOrEdit(existing: f),
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemCount: _items.length,
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addOrEdit,
        icon: const Icon(Icons.add_rounded),
        label: Text(getTranslated(context, 'Add favorite')),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_border_rounded,
                size: 64, color: Colors.black45),
            const SizedBox(height: 10),
            Text(
              getTranslated(context, 'No favorites yet'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              getTranslated(
                  context, 'Save Home, Work, or any place you visit often.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addOrEdit,
              icon: const Icon(Icons.add_rounded),
              label: Text(getTranslated(context, 'Add your first favorite')),
            )
          ],
        ),
      ),
    );
  }
}

// ---------- PUBLIC MODEL (made public so MainScreen can use it) ----------
class FavoritePlace {
  final String id;
  final String label; // e.g., "Home"
  final String address; // readable address
  final double lat;
  final double lng;
  final String type; // Home/Work/School/Other

  FavoritePlace({
    required this.id,
    required this.label,
    required this.address,
    required this.lat,
    required this.lng,
    required this.type,
  });

  LatLng get latLng => LatLng(lat, lng);

  Map<String, dynamic> toMap() => {
        'label': label,
        'address': address,
        'lat': lat,
        'lng': lng,
        'type': type,
      };

  factory FavoritePlace.fromMap(String id, Map<Object?, Object?> m) {
    return FavoritePlace(
      id: id,
      label: (m['label'] ?? '') as String,
      address: (m['address'] ?? '') as String,
      lat: (m['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (m['lng'] as num?)?.toDouble() ?? 0.0,
      type: (m['type'] ?? 'Other') as String,
    );
  }
}

class _FavoriteEditor extends StatefulWidget {
  final PlacesService places;
  final FavoritePlace? initial;

  const _FavoriteEditor({
    required this.places,
    this.initial,
  });

  @override
  State<_FavoriteEditor> createState() => _FavoriteEditorState();
}

class _FavoriteEditorState extends State<_FavoriteEditor> {
  final _labelCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _addressFocus = FocusNode();

  String _type = 'Home';
  LatLng? _pickedLL;

  // Bias center for autocomplete
  LatLng? _biasCenter;

  List<PlaceSuggestion> _suggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();

    if (widget.initial != null) {
      _labelCtrl.text = widget.initial!.label;
      _addressCtrl.text = widget.initial!.address;
      _pickedLL = widget.initial!.latLng;
      _type = widget.initial!.type;
    }

    _initBiasCenter();
  }

  Future<void> _initBiasCenter() async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        setState(() => _biasCenter = const LatLng(24.7136, 46.6753));
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _biasCenter = const LatLng(24.7136, 46.6753));
        return;
      }
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.low);
      setState(() => _biasCenter = LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      setState(() => _biasCenter = const LatLng(24.7136, 46.6753));
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _addressCtrl.dispose();
    _addressFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onAddressChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (q.trim().isEmpty) {
        setState(() => _suggestions = []);
        return;
      }
      widget.places.startSession();
      final list = await widget.places.autocomplete(
        input: q,
        biasCenter: _biasCenter ?? const LatLng(24.7136, 46.6753),
      );
      if (!mounted) return;
      setState(() => _suggestions = list);
    });
  }

  Future<void> _pickSuggestion(PlaceSuggestion s) async {
    final ll = await widget.places.detailsLatLng(placeId: s.placeId);
    widget.places.endSession();
    if (ll == null) return;
    setState(() {
      _addressCtrl.text = s.title;
      _pickedLL = ll;
      _suggestions = [];
    });
  }

  bool get _canSave =>
      _labelCtrl.text.trim().isNotEmpty &&
      _addressCtrl.text.trim().isNotEmpty &&
      _pickedLL != null;

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initial != null;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Grab handle
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),

                Text(
                  isEditing
                      ? getTranslated(context, 'Edit favorite')
                      : getTranslated(context, 'Add favorite'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),

                // Type chips
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in const ['Home', 'Work', 'School', 'Other'])
                      ChoiceChip(
                        label: Text(t),
                        selected: _type == t,
                        onSelected: (_) => setState(() => _type = t),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Label
                TextField(
                  controller: _labelCtrl,
                  decoration: InputDecoration(
                    labelText: getTranslated(context, 'Label'),
                    hintText: getTranslated(context, 'e.g., Home'),
                    filled: true,
                    fillColor: Colors.white,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),

                // Address search
                SearchField(
                  hint: getTranslated(context, 'Search address'),
                  controller: _addressCtrl,
                  onChanged: _onAddressChanged,
                  onSubmitted: (_) {},
                  showClearButton: true,
                  focusNode: _addressFocus,
                ),

                if (_suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(blurRadius: 6, color: Colors.black12)
                      ],
                    ),
                    constraints: BoxConstraints(
                      maxHeight: math.min(
                          300, MediaQuery.of(context).size.height * 0.45),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const ClampingScrollPhysics(),
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final s = _suggestions[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined),
                          title: Text(
                            s.title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            s.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _pickSuggestion(s),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(getTranslated(context, 'Cancel')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _canSave
                            ? () {
                                final fav = FavoritePlace(
                                  id: widget.initial?.id ?? 'new',
                                  label: _labelCtrl.text.trim(),
                                  address: _addressCtrl.text.trim(),
                                  lat: _pickedLL!.latitude,
                                  lng: _pickedLL!.longitude,
                                  type: _type,
                                );
                                Navigator.of(context).pop(fav);
                              }
                            : null,
                        icon: const Icon(Icons.save_rounded),
                        label: Text(getTranslated(context, 'Save')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
