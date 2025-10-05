import 'dart:async';
import 'dart:math' as math;
import 'dart:math';
import 'dart:ui' as ui;

import 'package:darb/extension/sized_box_extension.dart';
import 'package:darb/screens/ticket_screen.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

// Favorites (for searching & returning a picked favorite)
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../constants/colors.dart';
import '../services/local_notifications.dart';
import '../widgets/all_metro_lines.dart'; // metroLineColors
import '../widgets/onboard_display.dart';
import '../widgets/shimmers.dart';
import 'account_drawer_screen.dart';
import '../widgets/bottom_navigation_bar.dart';
import '../widgets/filter_chip_pill.dart';
import '../widgets/main_screen_widgets/mode_icon.dart';
import '../widgets/verify_banner.dart';
import '../widgets/search_field.dart';
import '../widgets/circle_action.dart';
import './discover_places_screen.dart';

import '../latlon/latlong_stations.dart' as metro;
import '../latlon/latlong_stations_directions.dart' as metroPolys;

import '../classes/route_option.dart';
import '../classes/gEdge.dart';
import '../classes/station_node.dart';
import '../localization/language_constants.dart';

import '../routing/metro_graph.dart';
import '../services/places_service.dart';
import '../services/directions_service.dart'; // <-- we use DriveRoute + computeDriveAlternatives
import '../widgets/route_options.dart';
import '../widgets/trip_preview_sheet.dart';
import '../utils/geo_utils.dart';
import '../utils/metro_hours.dart';
import '../widgets/metro_closed_sheet.dart';
import 'favorites_screen.dart';

// NEW: travel history writes
import '../services/travel_history_service.dart';
import '../services/nav_session.dart';
import 'line_segment_picker_screen.dart';

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

// ---------- Suggestion union (Place or Favorite) ----------
class _Suggest {
  final String kind; // 'place' | 'favorite'
  final PlaceSuggestion? place;
  final FavoritePlace? fav;

  _Suggest.place(this.place)
      : kind = 'place',
        fav = null;

  _Suggest.fav(this.fav)
      : kind = 'favorite',
        place = null;

  String get title => kind == 'place' ? place!.title : fav!.label;
  String get subtitle => kind == 'place' ? place!.subtitle : fav!.address;
  IconData get icon {
    if (kind == 'place') return Icons.place_outlined;
    switch ((fav!.type).toLowerCase()) {
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
}

enum _ActiveField { none, origin, destination }

enum _TripMode { metro, drive }

enum NavHintType { walk, board, transfer, alight }

class MainScreen extends StatefulWidget {
  final String firstName;
  final bool emailVerified;
  const MainScreen(
      {super.key, required this.firstName, required this.emailVerified});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  // --- NAV HINT (floating card) -----------------------------------------------
// --- Nav prompt guards ---
  bool _walkFirstPromptDone =
      false; // shown "walk to first" and/or reached first station
  final Set<String> _transferNextShown =
      {}; // track which "transfer at next" prompts we already showed

  OverlayEntry? _navHintEntry;

  void _showNavHint(
    NavHintType type,
    String text, {
    Duration duration = const Duration(seconds: 4),
  }) {
    // Close any currently visible hint
    _navHintEntry?.remove();
    _navHintEntry = null;

    Color bg;
    IconData icon;
    switch (type) {
      case NavHintType.walk:
        bg = const Color(0xFF263238);
        icon = Icons.directions_walk_rounded;
        break;
      case NavHintType.board:
        bg = const Color(0xFF1B5E20);
        icon = Icons.directions_subway_filled;
        break;
      case NavHintType.transfer:
        bg = const Color(0xFFFB8C00);
        icon = Icons.swap_horiz_rounded;
        break;
      case NavHintType.alight:
        bg = const Color(0xFFE53935);
        icon = Icons.flag_rounded;
        break;
    }

    final entry = OverlayEntry(
      builder: (ctx) => Positioned(
        left: 12,
        right: 12,
        bottom: 96, // sits above FABs / bottom nav
        child: SafeArea(
          top: false,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                      blurRadius: 12,
                      color: Colors.black26,
                      offset: Offset(0, 6)),
                ],
              ),
              child: Row(
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    splashRadius: 18,
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      _navHintEntry?.remove();
                      _navHintEntry = null;
                    },
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(entry);
    _navHintEntry = entry;

    Future.delayed(duration, () {
      if (_navHintEntry == entry) {
        _navHintEntry?.remove();
        _navHintEntry = null;
      }
    });
  }

  bool get _isInForeground => _lifecycle == AppLifecycleState.resumed;
  // === Metro ETA model (average run + dwell at stops) ===
  static const double _METRO_CRUISE_MPS = 16.7; // ~60 km/h average along track
  static const int _DWELL_SECS = 22; // avg dwell 15–30s per stop
  String _fmtClock(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String? _lastTransferKey; // "<stationId>|<toLineKey>"

  String? _metroCurLineKey; // current line user is riding
  int _stopsLeftOnLine = 0; // remaining stops on current line (updates live)
  bool _transferAtNext = false; // if the NEXT station is a transfer point
  String? _transferToLineKey; // line to switch to at that transfer

  DateTime? _nearDestSince;
  DateTime? _nearFinalSince;
  // Show-state for station snapping in tunnels
  int _lastLegShown = -1; // last leg index we rendered on the map
  bool _justAcceptedRaw =
      false; // one-tick flag when we accept a raw recovery fix

// Metro progress hysteresis
  int _metroLeg = 0;
  DateTime? _nearNextSince;
  double _nextMinDist = double.infinity;

// Metro filtering / map-matching
  static const double _metroMaxSpeedMps = 25.0; // sanity cap
  static const double _metroCorridorMeters = 80.0; // normal corridor to track
  static const double _recoveryCorridorM =
      220.0; // corridor after long GPS gaps
  static const int recoverGapSecs = 8; // consider "after tunnel" if gap > this

// Breadcrumb version (used only for car mode)
  int _trailVersion = 0;
  List<StationNode> _metroSeq = [];
  String? _metroNextName;
  String? _metroAfterName;
  bool _metroAlightAtNext = false;
  // Map
  final Completer<GoogleMapController> _mapController = Completer();
  static const LatLng _riyadh = LatLng(24.7136, 46.6753);
  CameraPosition _camera = const CameraPosition(target: _riyadh, zoom: 12.5);
  RouteOption? _lastChosenRoute;
  List<RouteOption>? _lastRouteOptions;
  String? _lastDestLabel;
  BitmapDescriptor? _navArrowIcon; // rendered once
  Marker? _userArrowMarker; // updated every fix
  int _offRouteStreak = 0; // consecutive ticks off the selected route
  bool _isRerouting = false; // guard so we don't reroute twice at once
  DateTime _lastRerouteAt = DateTime.fromMillisecondsSinceEpoch(0);
  // Location
  bool _locationGranted = false;
  bool _initialCentered = false;
  bool _checkingLocation = true;
  Position? _lastKnownPosition;

  // User origin/destination
  LatLng? _userOrigin;
  LatLng? _userDestination;
  LatLng _lastCameraTarget = _riyadh;
  final NavSession _bgNav = NavSession.instance;
  StreamSubscription<NavUpdate>? _uiNavSub;

  // Search + suggestions
  final TextEditingController _originCtrl = TextEditingController();
  final TextEditingController _destCtrl = TextEditingController();
  final FocusNode _originFocus = FocusNode();
  final FocusNode _destFocus = FocusNode();
  _ActiveField _active = _ActiveField.none;

  Timer? _debounce;
  List<_Suggest> _suggestions = [];

  // Favorites cache for searching
  final _db = FirebaseDatabase.instance;
  final _auth = FirebaseAuth.instance;
  DatabaseReference? _favRef;
  StreamSubscription<DatabaseEvent>? _favSub;
  List<FavoritePlace> _favorites = [];

  // Overlays
  Set<Polyline> _routePolylines = {};
  Set<Marker> _routeMarkers = {};
  Set<Marker> _stationMarkers = {};
  Set<Circle> _highlightCircles = {};
  bool _showAllLinesUnderRoute = false;
  bool _trafficEnabled = false; // only true during driving routes

  String? _selectedLineKey;

  // Data/engines
  late final MetroGraph _graph;
  final _places = PlacesService();
  final _dirs =
      DirectionsService(); // <-- same, reuses kDirectionsApiKey internally

  // Destination fancy marker
  BitmapDescriptor? _destIcon;
  Marker? _destMarker;
  // Draggable sheet controller
  final DraggableScrollableController _homeSheetCtrl =
      DraggableScrollableController();

  // Trip mode (Metro / Car)
  _TripMode _tripMode = _TripMode.metro;

  // ======= Simple in-app Navigation state =======
  StreamSubscription<Position>? _navSub;
  bool _navigating = false;
  List<LatLng> _navPoints = [];
  Polyline? _navPolyline;
  LatLng? _navDestination;
  double _navRemainingMeters = 0;
  double _navSpeedMps = 0;

  // ======= Travel history session state =======
  final _travelSvc = TravelHistoryService();
  String? _activeTripId; // push key in DB
  DateTime? _tripStartAt;
  int _tripDistance = 0; // meters accumulated
  LatLng? _lastNavPoint;
  String? _tripOriginLabel;
  String? _tripDestLabel;
  LatLng? _tripOriginLL;
  LatLng? _tripDestLL;

  // ======= NEW: Car mode multi-route + banner state =======
  List<DriveRoute>? _driveAlternates; // from Routes API v2
  int _drivePick = 0;

  // Keep steps dynamic (the StepInfo type in service is private)
  List<dynamic> _navSteps = [];
  int _navStepIndex = 0;
  String? _navNow;
  String? _navNext;

  // ======= Smoothing additions =======
  DateTime _lastCamMoveAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _camBusy = false;

  DateTime _lastFixAt = DateTime.now();
  Timer? _predictTimer;
  LatLng? _lastFixLL;
  double _lastFixSpeed = 0; // m/s
  double _lastFixHeading = 0; // degrees
  LatLng _mid(List<LatLng> pts) => pts[pts.length ~/ 2];
  bool _followEnabled = true; // when false, camera won’t auto-follow
  // Return nearest point on current leg's metro polyline to p, plus distance (meters).
// If the leg or polyline is missing, returns (p, +inf) so caller can decide.

  double _polylineLengthMeters(List<LatLng> pts) {
    if (pts.length < 2) return 0;
    double sum = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      sum += Geolocator.distanceBetween(
        pts[i].latitude,
        pts[i].longitude,
        pts[i + 1].latitude,
        pts[i + 1].longitude,
      );
    }
    return sum;
  }

  double _remainingOnLegMeters(LatLng here, List<LatLng> legPoly) {
    if (legPoly.length < 2) return 0;

    // find closest vertex (simple, robust)
    int nearest = 0;
    double best = double.infinity;
    for (int i = 0; i < legPoly.length; i++) {
      final d = Geolocator.distanceBetween(
        here.latitude,
        here.longitude,
        legPoly[i].latitude,
        legPoly[i].longitude,
      );
      if (d < best) {
        best = d;
        nearest = i;
      }
    }

    // sum from nearest point to end of leg
    double rem = 0;
    for (int i = nearest; i < legPoly.length - 1; i++) {
      rem += Geolocator.distanceBetween(
        legPoly[i].latitude,
        legPoly[i].longitude,
        legPoly[i + 1].latitude,
        legPoly[i + 1].longitude,
      );
    }
    return rem;
  }

  ({LatLng pos, double distanceM}) _mapMatchToMetroLeg(LatLng p) {
    if (_metroSeq.length < 2) return (pos: p, distanceM: double.infinity);
    final int leg = _metroLeg.clamp(0, _metroSeq.length - 2);
    final StationNode a = _metroSeq[leg];
    final StationNode b = _metroSeq[leg + 1];
    final List<LatLng> poly =
        _slicePolylineByStations(a.lineKey, a.index, b.index);
    if (poly.length < 2) return (pos: p, distanceM: double.infinity);

    double best = double.infinity;
    LatLng bestPt = poly.first;
    for (int i = 0; i < poly.length - 1; i++) {
      final m = _projectPointOnSegmentMeters(p, poly[i], poly[i + 1]);
      if (m.$2 < best) {
        best = m.$2;
        bestPt = m.$1;
      }
    }
    return (pos: bestPt, distanceM: best);
  }

  ({LatLng pos, double distanceM, int legIdx}) _mapMatchToWholeMetro(LatLng p) {
    if (_metroSeq.length < 2)
      return (pos: p, distanceM: double.infinity, legIdx: 0);
    double best = double.infinity;
    LatLng bestPt = _metroSeq.first.pos;
    int bestLeg = 0;

    for (int leg = 0; leg < _metroSeq.length - 1; leg++) {
      final a = _metroSeq[leg], b = _metroSeq[leg + 1];
      final List<LatLng> poly =
          _slicePolylineByStations(a.lineKey, a.index, b.index);
      for (int i = 0; i < poly.length - 1; i++) {
        final m = _projectPointOnSegmentMeters(p, poly[i], poly[i + 1]);
        if (m.$2 < best) {
          best = m.$2;
          bestPt = m.$1;
          bestLeg = leg;
        }
      }
    }
    return (pos: bestPt, distanceM: best, legIdx: bestLeg);
  }

  (LatLng, double) _projectPointOnSegmentMeters(LatLng p, LatLng a, LatLng b) {
    const mPerDegLat = 111320.0;
    final mPerDegLon = 111320.0 * math.cos((p.latitude * math.pi) / 180.0);
    final ax = a.latitude * mPerDegLat, ay = a.longitude * mPerDegLon;
    final bx = b.latitude * mPerDegLat, by = b.longitude * mPerDegLon;
    final px = p.latitude * mPerDegLat, py = p.longitude * mPerDegLon;
    final vx = bx - ax, vy = by - ay, wx = px - ax, wy = py - ay;
    final c1 = vx * wx + vy * wy, c2 = vx * vx + vy * vy;
    double t = (c2 <= 0) ? 0 : (c1 / c2);
    t = t.clamp(0.0, 1.0);
    final projx = ax + t * vx, projy = ay + t * vy;
    final dx = px - projx, dy = py - projy;
    final lat = projx / mPerDegLat, lon = projy / mPerDegLon;
    return (LatLng(lat, lon), math.sqrt(dx * dx + dy * dy));
  }

  Future<void> _prepareNavArrowIcon() async {
    if (_navArrowIcon != null) return;

    final dpr = MediaQueryData.fromWindow(ui.window).devicePixelRatio;
    final int size = (36.0 * dpr).round(); // logical 36
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    );
    final paint = Paint()..isAntiAlias = true;
    final cx = size / 2.0, cy = size / 2.0;

    // White ring
    paint.color = Colors.white;
    canvas.drawCircle(Offset(cx, cy), size * 0.48, paint);

    // Blue disk
    paint.color = const Color(0xFF1E88E5);
    canvas.drawCircle(Offset(cx, cy), size * 0.42, paint);

    // White arrow pointing up (will rotate with heading)
    final r = size * 0.30;
    final arrow = Path()
      ..moveTo(cx, cy - r) // tip
      ..lineTo(cx - r * 0.62, cy + r * 0.70)
      ..lineTo(cx + r * 0.62, cy + r * 0.70)
      ..close();
    paint.color = Colors.white;
    canvas.drawPath(arrow, paint);

    final img = await recorder.endRecording().toImage(size, size);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    _navArrowIcon = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _etaBadgeIconCompact({
    required String minsLabel, // e.g. "21 min"
    String? deltaLabel, // e.g. "+3"
    bool selected = false, // true = green (selected), else dark gray
  }) async {
    final dpr = ui.window.devicePixelRatio;

    // Fonts (logical sizes) – small and bold like Google Maps
    final double mainFs = 12.0 * dpr;
    final double subFs = 10.0 * dpr;

    // Build text painters
    final mainTp = TextPainter(
      text: TextSpan(
        text: minsLabel,
        style: TextStyle(
          color: Colors.white,
          fontSize: mainFs,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final subTp = (deltaLabel != null && deltaLabel.isNotEmpty)
        ? (TextPainter(
            text: TextSpan(
              text: deltaLabel,
              style: TextStyle(
                color: const Color(0xFFE57373), // soft red
                fontSize: subFs,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout())
        : null;

    // Padding and dimensions (logical px, then multiplied by dpr)
    const double padH = 8.0; // left/right padding
    const double padV = 6.0; // top/bottom padding per text block

    // Two-line height if we have delta, else single-line pill
    final double logicalH = (subTp == null) ? (28.0) : (34.0);
    final double contentW = math.max(mainTp.width, subTp?.width ?? 0);
    final double logicalW = (contentW / dpr) + (padH * 2);

    final int w = (logicalW * dpr).round().clamp(64, 200);
    final int h = (logicalH * dpr).round();

    final recorder = ui.PictureRecorder();
    final canvas =
        Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    final bg = Paint()
      ..isAntiAlias = true
      ..color = selected ? const Color(0xFF1B5E20) : const Color(0xFF263238);

    // Rounded pill
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      const Radius.circular(10),
    );
    canvas.drawRRect(r, bg);

    // Draw texts centered
    final mainX = (w - mainTp.width) / 2;
    final mainY = (subTp == null)
        ? (h - mainTp.height) / 2
        : (h / 2 - mainTp.height + 2); // slight nudge up for 2-line

    mainTp.paint(canvas, Offset(mainX, mainY));

    if (subTp != null) {
      final subX = (w - subTp.width) / 2;
      final subY = (h / 2 + 2); // slight nudge down
      subTp.paint(canvas, Offset(subX, subY));
    }

    final img = await recorder.endRecording().toImage(w, h);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<void> _rebuildDriveEtaBadges() async {
    if (_driveAlternates == null) return;

    // Keep existing non-ETA markers
    final markers = <Marker>{
      ..._routeMarkers.where((m) => !m.markerId.value.startsWith('drive_eta_'))
    };

    final best =
        _driveAlternates!.map((r) => r.durationSeconds).reduce(math.min);

    for (int i = 0; i < _driveAlternates!.length; i++) {
      final r = _driveAlternates![i];
      final mins = (r.durationSeconds / 60).round();
      final delta = r.durationSeconds - best;
      final minsLabel = '$mins min';
      final deltaLabel = (delta > 0) ? '+${(delta / 60).round()}' : null;

      final icon = await _etaBadgeIconCompact(
        minsLabel: minsLabel,
        deltaLabel: deltaLabel,
        selected: i == _drivePick, // green if selected
      );

      // Place near the route midpoint
      final mid = r.points[r.points.length ~/ 2];

      markers.add(Marker(
        markerId: MarkerId('drive_eta_$i'),
        position: mid,
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        zIndex: i == _drivePick ? 2001 : 1201,
        onTap: () => _onPickDrive(i), // tap badge to select
      ));
    }

    setState(() => _routeMarkers = markers);
  }

  bool _snapToNearestAlternateIfCloser(LatLng here, {double snapMeters = 35}) {
    if (_tripMode != _TripMode.drive) return false;
    if (_driveAlternates == null || _driveAlternates!.isEmpty) return false;

    final selected = _driveAlternates![_drivePick];
    double bestD = _distancePointToPolylineMeters(here, selected.points);
    int bestI = _drivePick;

    for (int i = 0; i < _driveAlternates!.length; i++) {
      final d =
          _distancePointToPolylineMeters(here, _driveAlternates![i].points);
      if (d < bestD) {
        bestD = d;
        bestI = i;
      }
    }

    // If you're clearly closer to another alternate, switch to it
    if (bestI != _drivePick && bestD < snapMeters) {
      _onPickDrive(bestI); // seeds steps, banner, redraws
      return true;
    }
    return false;
  }

  void _onPickDrive(int i) {
    if (_driveAlternates == null || i < 0 || i >= _driveAlternates!.length)
      return;
    setState(() => _drivePick = i);
    _drawDrivePolylines(); // redraw widths/colors
    _rebuildDriveEtaBadges(); // re-label alternates

    // Seed current/next instructions for the newly picked route
    final r = _driveAlternates![i];
    _navSteps = r.steps;
    _navStepIndex = 0;
    _navNow = _navSteps.isNotEmpty
        ? (_navSteps.first.instruction ?? getTranslated(context, 'nav.start'))
        : getTranslated(context, 'nav.start');
    _navNext = _navSteps.length > 1
        ? (_navSteps[1].instruction ?? getTranslated(context, 'nav.continue'))
        : null;
  }

  // Bearing from A to B (degrees 0..360)
  double _bearing(LatLng a, LatLng b) {
    final dLon = (b.longitude - a.longitude) * (math.pi / 180);
    final lat1 = a.latitude * (math.pi / 180);
    final lat2 = b.latitude * (math.pi / 180);
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
    return brng;
  }

  // distance from a point to the closest part of a polyline (meters)
  double _distancePointToPolylineMeters(LatLng p, List<LatLng> line) {
    if (line.length < 2) return double.infinity;
    double best = double.infinity;
    for (int i = 0; i < line.length - 1; i++) {
      best = math.min(
          best, _distancePointToSegmentMeters(p, line[i], line[i + 1]));
    }
    return best;
  }

  double _distancePointToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    const mPerDegLat = 111320.0;
    final mPerDegLon = 111320.0 * math.cos((p.latitude * math.pi) / 180.0);

    final axm = a.latitude * mPerDegLat, aym = a.longitude * mPerDegLon;
    final bxm = b.latitude * mPerDegLat, bym = b.longitude * mPerDegLon;
    final pxm = p.latitude * mPerDegLat, pym = p.longitude * mPerDegLon;

    final vx = bxm - axm, vy = bym - aym;
    final wx = pxm - axm, wy = pym - aym;
    final c1 = vx * wx + vy * wy;
    final c2 = vx * vx + vy * vy;
    double t = (c2 <= 0) ? 0 : (c1 / c2);
    t = t.clamp(0.0, 1.0);
    final projx = axm + t * vx, projy = aym + t * vy;
    final dx = pxm - projx, dy = pym - projy;
    return math.sqrt(dx * dx + dy * dy);
  }

  void _clearPlannedTrip({bool keepDestMarker = false}) {
    // If a trip is currently running, stop it first.
    if (_navigating) {
      _endTrip();
    }

    setState(() {
      // wipe routing state (metro + driving)
      _lastChosenRoute = null;
      _lastRouteOptions = null;
      _driveAlternates = null;
      _drivePick = 0;
      _navSteps = [];
      _navStepIndex = 0;
      _navNow = null;
      _navNext = null;

      // map overlays
      _routePolylines.clear();
      _routeMarkers.clear();
      _stationMarkers.clear();
      _showAllLinesUnderRoute = false;
      _selectedLineKey = null;
      _trafficEnabled = false;

      // destination marker & labels
      if (!keepDestMarker) {
        _clearDestinationMarker();
        _userDestination = null;
        _lastDestLabel = null;
      }
    });
  }

  Future<void> _rerouteFrom(LatLng here) async {
    if (_navDestination == null) return;
    await _renderDrivingRoute(here, _navDestination!);
  }

  Future<void> _startTrip() async {
    if (_userDestination == null) {
      _notify(getTranslated(context, 'Pick a destination first.'));
      return;
    }
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      _notify(getTranslated(context, 'Location permission denied.'));
      return;
    }

    // resets
    _nearDestSince = null;
    _nearFinalSince = null;
    _metroLeg = 0;
    _nearNextSince = null;
    _nextMinDist = double.infinity;

    // >>> NEW: prompt-guards (ensure walk-to-first & transfer-next don’t repeat)
    _walkFirstPromptDone = false;
    _transferNextShown.clear();
    // <<<

    _tripDestLabel =
        _destCtrl.text.isNotEmpty ? _destCtrl.text : _tripDestLabel;
    _tripDestLL = _userDestination;
    _tripOriginLabel =
        _originCtrl.text.isNotEmpty ? _originCtrl.text : _tripOriginLabel;
    _tripOriginLL = _userOrigin ??
        (_lastKnownPosition != null
            ? LatLng(
                _lastKnownPosition!.latitude, _lastKnownPosition!.longitude)
            : _lastCameraTarget);

    final modeStr = (_tripMode == _TripMode.metro) ? 'metro' : 'car';
    _tripStartAt = DateTime.now();
    _tripDistance = 0;
    _lastNavPoint = null;

    // Collect metro “context” for history (safe if not in metro)
    final List<String> _chosenLines = (_lastChosenRoute?.lineSequence ?? [])
        .map((s) => s.toString())
        .toList();

    String? _fromStationName;
    String? _toStationName;
    if (_lastChosenRoute != null) {
      // first & last metro nodes on the chosen route
      final firstMetroId = _lastChosenRoute!.nodeIds.firstWhere(
        (id) => id.contains(':'),
        orElse: () => '',
      );
      final lastMetroId = _lastChosenRoute!.nodeIds.reversed.firstWhere(
        (id) => id.contains(':'),
        orElse: () => '',
      );
      if (firstMetroId.isNotEmpty) {
        _fromStationName = _lastChosenRoute!.nodes[firstMetroId]?.name;
      }
      if (lastMetroId.isNotEmpty) {
        _toStationName = _lastChosenRoute!.nodes[lastMetroId]?.name;
      }
    }

    _activeTripId = await _travelSvc.startTrip(
      mode: modeStr, // 'metro' | 'car'
      originLabel: _tripOriginLabel,
      destLabel: _tripDestLabel,
      originLL: _tripOriginLL,
      destLL: _tripDestLL,
      metroLineKeys: (_tripMode == _TripMode.metro)
          ? (_chosenLines
              ?.map((s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1))
              .toList())
          : null,
      fromStation: (_tripMode == _TripMode.metro) ? _fromStationName : null,
      toStation: (_tripMode == _TripMode.metro) ? _toStationName : null,
      startedAt: _tripStartAt,
    );

    // seed with current position
    final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best);
    _navDestination = _userDestination;
    final here0 = LatLng(pos.latitude, pos.longitude);
    _navPoints = [here0];
    _lastNavPoint = here0;

    _navRemainingMeters = Geolocator.distanceBetween(pos.latitude,
        pos.longitude, _navDestination!.latitude, _navDestination!.longitude);
    _navSpeedMps = pos.speed;

    // Car mode draws a breadcrumb; metro = no breadcrumb
    if (_tripMode == _TripMode.drive &&
        _driveAlternates != null &&
        _driveAlternates!.isNotEmpty) {
      final r = _driveAlternates![_drivePick];
      _navPolyline = Polyline(
        polylineId: PolylineId('nav_trace_${_trailVersion++}'),
        color: Colors.grey.shade600,
        width: 6,
        points: _navPoints,
        zIndex: 3000,
      );
      _navSteps = r.steps;
      _navStepIndex = 0;
      _navNow = _navSteps.isNotEmpty
          ? (_navSteps.first.instruction ?? getTranslated(context, 'nav.start'))
          : getTranslated(context, 'nav.start');
      _navNext = _navSteps.length > 1
          ? (_navSteps[1].instruction ?? getTranslated(context, 'nav.continue'))
          : null;
    } else {
      _navPolyline = null; // <<< no trail in metro
    }

    await _prepareNavArrowIcon();

    setState(() {
      _navigating = true;
      _followEnabled = true;
      _offRouteStreak = 0;
      _isRerouting = false;
    });

    // ---- Metro leg setup + initial "walk to first station" hint (one-shot) ---
    if (_tripMode == _TripMode.metro && _lastChosenRoute != null) {
      _metroSeq = _lastChosenRoute!.nodeIds
          .where((id) => id.contains(':'))
          .map((id) => _lastChosenRoute!.nodes[id]!)
          .toList();

      _metroLeg = 0;
      _nearNextSince = null;
      _nextMinDist = double.infinity;
      _metroNextName = (_metroSeq.length >= 2) ? _metroSeq[1].name : null;
      _metroAfterName = (_metroSeq.length >= 3) ? _metroSeq[2].name : null;
      _metroAlightAtNext =
          (_metroSeq.length >= 2) && (_metroSeq[1].id == _metroSeq.last.id);

      if (_metroSeq.isNotEmpty) {
        final first = _metroSeq.first;
        final d = Geolocator.distanceBetween(
          here0.latitude,
          here0.longitude,
          first.pos.latitude,
          first.pos.longitude,
        );
        // (no immediate snackbar here; alerts handled in stream)
      }
    }

    await _bgNav.start(dest: _navDestination!);
    _attachNavStream();
  }

  void _attachNavStream() {
    _uiNavSub?.cancel();

    // ── De-dupe + background-delivery for alerts ───────────────────────────────
    // (clears whenever this method is called, i.e., per trip/session)
    final Map<String, DateTime> _alertShownAt = {};
    const Duration _alertCooldown = Duration(seconds: 45);

    // >>> NEW: foreground uses floating hint; timing and de-dupe preserved
    void _notifyOnce(String key, String message,
        {NavHintType type = NavHintType.walk}) {
      // Don't nag when not actually navigating (prevents spam on the Home sheet)
      if (!_navigating) return;

      final now = DateTime.now();
      final last = _alertShownAt[key];
      if (last == null || now.difference(last) >= _alertCooldown) {
        _alertShownAt[key] = now;

        // Show in-app (only if we're visible) AND always post a local notification
        if (_isInForeground && mounted) {
          _showNavHint(type, message); // floating hint (no SnackBar)
          HapticFeedback.selectionClick();
        }
        AppLocalNotifications.show(body: message); // works in background/closed
      }
    }
    // <<<

    _uiNavSub = _bgNav.updates.listen((u) async {
      final now = DateTime.now();
      final bool isRealFix = !u.predicted;
      LatLng here = u.here;
      LatLng uiPos;
      final prev = _lastNavPoint;

      // Car dead-reckoning allowed only when moving & short gap
      final drAllowed = (_tripMode == _TripMode.drive) &&
          (u.speedMps.isFinite && u.speedMps > 1.4) &&
          now.difference(_lastFixAt).inMilliseconds < 2500;

      // ── Metro: validate, recover, map-match ──────────────────────────────────
      bool metroAccept = true;
      _justAcceptedRaw = false;

      if (isRealFix && _tripMode == _TripMode.metro) {
        // Reject absurd speeds
        if (u.speedMps.isFinite && u.speedMps > _metroMaxSpeedMps) {
          metroAccept = false;
        }

        // Corridor depends on GPS gap (recovery after tunnel)
        final gapSecs = now.difference(_lastFixAt).inSeconds;
        final corridor = (gapSecs > recoverGapSecs)
            ? _recoveryCorridorM
            : _metroCorridorMeters;

        // Try leg map-match
        var mm = _mapMatchToMetroLeg(here);
        if (mm.distanceM > corridor) {
          // Whole-route recovery
          final all = _mapMatchToWholeMetro(here);
          if (all.distanceM <= _recoveryCorridorM) {
            here = all.pos;
            _metroLeg = all.legIdx;
            mm = (pos: all.pos, distanceM: all.distanceM);
            metroAccept = true;
          } else {
            // FINAL RECOVERY: accept raw fix ONCE to re-anchor (no teleporting)
            final double jumpFromPrev =
                (prev == null) ? 0.0 : _distMeters(prev, here);
            final bool saneJump = jumpFromPrev <= 800.0; // ~0.8 km cap
            if (gapSecs > recoverGapSecs && saneJump) {
              metroAccept = true;
              _justAcceptedRaw = true;
            } else {
              metroAccept = false;
            }
          }
        } else {
          here = mm.pos; // snap to leg
        }
      }

      // ── Station snap when leg advanced but no accepted fix ───────────────────
      LatLng? stationSnap;
      if (_tripMode == _TripMode.metro &&
          _metroSeq.length >= 2 &&
          _lastLegShown != _metroLeg &&
          !(isRealFix && metroAccept)) {
        final int idx = (_metroLeg).clamp(0, _metroSeq.length - 1);
        stationSnap = _metroSeq[idx].pos;
      }

      // Decide UI position
      if (_tripMode == _TripMode.metro) {
        if (stationSnap != null) {
          uiPos = stationSnap;
        } else {
          uiPos = (isRealFix && metroAccept) ? here : (_lastNavPoint ?? here);
        }
      } else {
        uiPos = (isRealFix || drAllowed) ? here : (_lastNavPoint ?? here);
      }

      // ── Distance / trail ─────────────────────────────────────────────────────
      if (_tripMode == _TripMode.drive) {
        if (isRealFix && prev != null) {
          final seg = Geolocator.distanceBetween(
              prev.latitude, prev.longitude, uiPos.latitude, uiPos.longitude);
          if (seg.isFinite) _tripDistance += seg.round();
        }
        if (isRealFix &&
            (_navPoints.isEmpty || _distMeters(_navPoints.last, uiPos) >= 2)) {
          _navPoints.add(uiPos);
          _navPolyline =
              _navPolyline?.copyWith(pointsParam: List.of(_navPoints));
        }
      } else {
        // metro: no breadcrumb; still count distance on accepted or station-snap
        if ((isRealFix && metroAccept) && prev != null) {
          final seg = Geolocator.distanceBetween(
              prev.latitude, prev.longitude, uiPos.latitude, uiPos.longitude);
          if (seg.isFinite) _tripDistance += seg.round();
        }
      }

      // ── Marker / heading ─────────────────────────────────────────────────────
      double brg;
      if ((isRealFix && (_tripMode != _TripMode.metro || metroAccept)) &&
          prev != null &&
          _distMeters(prev, uiPos) > 1.5) {
        brg = _bearing(prev, uiPos);
      } else {
        brg = (drAllowed && _tripMode == _TripMode.drive)
            ? u.headingDeg
            : _lastFixHeading;
      }
      if (_navArrowIcon != null) {
        _userArrowMarker = Marker(
          markerId: const MarkerId('me_nav'),
          position: uiPos,
          icon: _navArrowIcon!,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          rotation: brg,
          zIndex: 4000,
        );
      }

      // ── Live status ──────────────────────────────────────────────────────────
      double uiSpeed = u.speedMps;
      if (_tripMode == _TripMode.metro) {
        if (!(isRealFix && metroAccept)) uiSpeed = 0.0;
      } else if (!isRealFix && !drAllowed) {
        uiSpeed = 0.0;
      }
      _navSpeedMps = uiSpeed;

      if (_navDestination != null) {
        _navRemainingMeters = Geolocator.distanceBetween(
            uiPos.latitude,
            uiPos.longitude,
            _navDestination!.latitude,
            _navDestination!.longitude);
      }

      // ── Car steps ────────────────────────────────────────────────────────────
      if (isRealFix && _tripMode == _TripMode.drive) _maybeAdvanceStep(here);

      // ── METRO leg advance hysteresis ─────────────────────────────────────────
      final bool canAdvanceMetro = (_tripMode == _TripMode.metro) &&
          (_metroSeq.length >= 2) &&
          ((isRealFix && metroAccept) || stationSnap != null);

      if (canAdvanceMetro) {
        _metroLeg = _metroLeg.clamp(0, _metroSeq.length - 2);
        final StationNode nextSt = _metroSeq[_metroLeg + 1];

        final double dNext = Geolocator.distanceBetween(uiPos.latitude,
            uiPos.longitude, nextSt.pos.latitude, nextSt.pos.longitude);

        _nextMinDist = math.min(_nextMinDist, dNext);

        const double ENTER_RADIUS = 120.0;
        const double ARRIVE_RADIUS = 45.0;
        const int LINGER_SECS = 2;
        const double PASS_DELTA = 20.0;

        if (dNext < ENTER_RADIUS) {
          _nearNextSince ??= now;
        } else {
          _nearNextSince = null;
          _nextMinDist = double.infinity;
        }

        bool arrivedNow = false;
        if (dNext < ARRIVE_RADIUS) {
          _nearNextSince ??= now;
          if (now.difference(_nearNextSince!).inSeconds >= LINGER_SECS) {
            arrivedNow = true;
          }
        }
        if (!arrivedNow &&
            _nextMinDist.isFinite &&
            (dNext - _nextMinDist) > PASS_DELTA) {
          arrivedNow = true;
        }

        if (arrivedNow) {
          if (_metroLeg + 1 < _metroSeq.length) {
            _metroLeg = (_metroLeg + 1).clamp(0, _metroSeq.length - 1);
          }
          _nearNextSince = null;
          _nextMinDist = double.infinity;
        }
      }

      // Remember for station-snap on next ticks
      _lastLegShown = _metroLeg;

      // ── Compose metro status + alerts (walk/transfer/alight) ─────────────────
      if (_tripMode == _TripMode.metro && _metroSeq.length >= 2) {
        final StationNode curr = _metroSeq[_metroLeg];
        final StationNode next =
            _metroSeq[math.min(_metroLeg + 1, _metroSeq.length - 1)];
        final String currLine = curr.lineKey;
        final String nextLine = next.lineKey;

        // Stops left on current line and (optional) transfer target
        int stopsLeftOnLine = 0;
        String? transferToLine;
        for (int i = _metroLeg; i < _metroSeq.length - 1; i++) {
          final a = _metroSeq[i];
          final b = _metroSeq[i + 1];
          if (a.lineKey != b.lineKey) {
            transferToLine = b.lineKey;
            break;
          }
          stopsLeftOnLine++;
        }

        final bool alightAtNext = (_metroLeg + 1 == _metroSeq.length - 1);
        final bool transferAtNext =
            (_metroLeg + 1 < _metroSeq.length - 1) && (nextLine != currLine);

        // Update banner fields for your UI
        _metroCurLineKey = currLine;
        _stopsLeftOnLine = stopsLeftOnLine;
        _metroNextName = next.name;
        _metroAfterName = (_metroLeg + 2 < _metroSeq.length)
            ? _metroSeq[_metroLeg + 2].name
            : null;
        _transferAtNext = transferAtNext;
        _transferToLineKey = transferToLine;
        _metroAlightAtNext = alightAtNext;

        // A) BEFORE BOARDING: show “Walk to FIRST station …” once and never again
        final StationNode first = _metroSeq.first;
        final bool stillBeforeBoard =
            (_metroLeg == 0); // not yet left first node
        final double dToFirst = Geolocator.distanceBetween(
          uiPos.latitude,
          uiPos.longitude,
          first.pos.latitude,
          first.pos.longitude,
        );

        // If you’re basically at the first station, lock out the prompt forever
        if (dToFirst < 80.0) {
          _walkFirstPromptDone = true;
        }

        if (stillBeforeBoard && !_walkFirstPromptDone && dToFirst > 120.0) {
          final msg = '${getTranslated(context, "Walk to")} ${first.name} '
              '${getTranslated(context, "to board the")} ${getTranslated(context, currLine)}';
          _notifyOnce('walk_board_once_${first.id}_$currLine', msg,
              type: NavHintType.board);
          _walkFirstPromptDone = true; // mark as shown immediately
        }

        // B) TRANSFER: announce one-stop ahead (like “Alight at next station”)
        if (transferAtNext && transferToLine != null) {
          final key = 'xfer_next_${next.id}_$transferToLine';
          if (!_transferNextShown.contains(key)) {
            final msg =
                '${getTranslated(context, "Change line at next station")} → '
                '${getTranslated(context, transferToLine)}}';
            _notifyOnce(key, msg, type: NavHintType.transfer);
            _transferNextShown.add(key);
          }
        }

        // C) ALIGHT AT NEXT (one-stop-ahead)
        if (alightAtNext && _metroLeg >= 1) {
          _notifyOnce(
            'alight_${next.id}',
            getTranslated(context, 'Alight at next station'),
            type: NavHintType.alight,
          );
        }
      }

      // ── Periodic progress write (every ~10s) ─────────────────────────────────
      final secs = now.difference(_tripStartAt ?? now).inSeconds;
      final okToWrite = isRealFix &&
          (_tripMode != _TripMode.metro || metroAccept || _justAcceptedRaw);
      if (okToWrite && _activeTripId != null && secs % 10 == 0) {
        await _travelSvc.updateProgress(
          entryId: _activeTripId!,
          distanceMeters: _tripDistance,
          durationSeconds: secs,
        );
      }

      // ── Car rerouting (unchanged) ────────────────────────────────────────────
      if (isRealFix &&
          _tripMode == _TripMode.drive &&
          _driveAlternates != null &&
          _driveAlternates!.isNotEmpty) {
        _snapToNearestAlternateIfCloser(here);
        final sel = _driveAlternates![_drivePick];
        final dSel = _distancePointToPolylineMeters(here, sel.points);
        final v =
            (_navSpeedMps.isFinite && _navSpeedMps >= 0) ? _navSpeedMps : 0.0;
        final offThr = v < 4.0 ? 45.0 : (v < 12.0 ? 65.0 : 85.0);
        if (dSel > offThr)
          _offRouteStreak++;
        else
          _offRouteStreak = 0;
        final longEnoughSinceLast =
            now.difference(_lastRerouteAt) > const Duration(seconds: 10);
        if (!_isRerouting && _offRouteStreak >= 5 && longEnoughSinceLast) {
          _isRerouting = true;
          setState(() {
            _navNow = getTranslated(context, 'Re-routing...');
            _navNext = null;
          });
          await _rerouteFrom(here);
          _offRouteStreak = 0;
          _isRerouting = false;
          _lastRerouteAt = now;
        }
      }

      // ── Camera follow ────────────────────────────────────────────────────────
      if (_tripMode == _TripMode.metro) {
        if ((isRealFix && metroAccept) || stationSnap != null) {
          await _throttledFollow(uiPos, _lastFixHeading,
              speedMps: _navSpeedMps);
        }
      } else if (isRealFix || drAllowed) {
        await _throttledFollow(uiPos, _lastFixHeading, speedMps: _navSpeedMps);
      }

      // ── Update "lasts" ───────────────────────────────────────────────────────
      if (_tripMode == _TripMode.metro) {
        if ((isRealFix && metroAccept) ||
            stationSnap != null ||
            _justAcceptedRaw) {
          _lastFixAt = now;
          _lastFixLL = uiPos;
          _lastFixSpeed = _navSpeedMps;
          _lastFixHeading = _lastFixHeading;
          _lastNavPoint = uiPos;
        }
      } else if (isRealFix || drAllowed) {
        _lastFixAt = now;
        _lastFixLL = uiPos;
        _lastFixSpeed = _navSpeedMps;
        _lastFixHeading = _lastFixHeading;
        _lastNavPoint = uiPos;
      }

      // ── Arrival detection (also notify in background) ────────────────────────
      bool allowFinalStationEnd = false;
      if (_tripMode == _TripMode.metro &&
          _metroSeq.isNotEmpty &&
          _tripDestLL != null) {
        final StationNode finalSt = _metroSeq.last;
        final double dToDestFromFinal = Geolocator.distanceBetween(
            finalSt.pos.latitude,
            finalSt.pos.longitude,
            _tripDestLL!.latitude,
            _tripDestLL!.longitude);
        allowFinalStationEnd = dToDestFromFinal <= 80.0;
      }

      if (_navDestination != null &&
          (isRealFix || stationSnap != null || _justAcceptedRaw)) {
        final moving = _navSpeedMps.isFinite && _navSpeedMps > 0.8;

        if (_navRemainingMeters < 65 && !moving) {
          _nearDestSince ??= now;
          if (now.difference(_nearDestSince!).inSeconds >= 8) {
            final msg = getTranslated(context, 'You have arrived.');
            if (_isInForeground && mounted) _notify(msg);
            AppLocalNotifications.show(body: msg);
            _endTrip();
            return;
          }
        } else {
          _nearDestSince = null;
        }

        if (allowFinalStationEnd) {
          final StationNode finalSt = _metroSeq.last;
          final double dFinal = Geolocator.distanceBetween(uiPos.latitude,
              uiPos.longitude, finalSt.pos.latitude, finalSt.pos.longitude);
          if (dFinal < 45 && !moving) {
            _nearFinalSince ??= now;
            if (now.difference(_nearFinalSince!).inSeconds >= 8) {
              final msg = getTranslated(context, 'You have arrived.');
              if (_isInForeground && mounted) _notify(msg);
              AppLocalNotifications.show(body: msg);
              _endTrip();
              return;
            }
          } else {
            _nearFinalSince = null;
          }
        } else {
          _nearFinalSince = null;
        }
      }

      if (isRealFix && _navDestination != null && _navRemainingMeters < 35) {
        final msg = getTranslated(context, 'You have arrived.');
        if (_isInForeground && mounted) _notify(msg);
        AppLocalNotifications.show(body: msg);
        _endTrip();
        return;
      }

      if (mounted) setState(() {});
    });
  }

  Future<void> _onRecenter() async {
    setState(() => _followEnabled = true);
    final here = _lastNavPoint ?? _lastCameraTarget;
    await _throttledFollow(here, _lastFixHeading, speedMps: _lastFixSpeed);
  }

  Future<void> _throttledFollow(LatLng target, double bearingDeg,
      {required double speedMps}) async {
    if (!_followEnabled) return;
    final now = DateTime.now();
    final shouldMove =
        now.difference(_lastCamMoveAt) > const Duration(milliseconds: 180);

    if (!shouldMove || !_mapController.isCompleted || _camBusy) return;

    _lastCamMoveAt = now;
    final ctrl = await _mapController.future;

    final cam = CameraPosition(
      target: target,
      zoom: 17.0,
      bearing: bearingDeg,
      tilt: (speedMps > 1.4) ? 50.0 : 0.0,
    );

    // For tiny deltas, moveCamera (instant); otherwise animate
    final prev = _lastNavPoint;
    final tinyShift =
        prev != null && _distMeters(prev, target) < 1.2 && (speedMps <= 1.4);
    if (tinyShift) {
      ctrl.moveCamera(CameraUpdate.newCameraPosition(cam));
    } else {
      _camBusy = true;
      await ctrl.animateCamera(CameraUpdate.newCameraPosition(cam));
      _camBusy = false;
    }
  }

  void _maybeAdvanceStep(LatLng here) {
    if (_tripMode != _TripMode.drive) return;
    if (_navSteps.isEmpty || _navStepIndex >= _navSteps.length) return;
    final step = _navSteps[_navStepIndex];
    final List<dynamic>? poly = step.poly as List<dynamic>?;
    final LatLng? tail =
        (poly != null && poly.isNotEmpty) ? poly.last as LatLng : null;
    if (tail == null) return;
    final d = Geolocator.distanceBetween(
        here.latitude, here.longitude, tail.latitude, tail.longitude);
    if (d < 25) {
      _navStepIndex++;

      final String contToDest = getTranslated(context, 'nav.continueToDest');

      _navNow = _navStepIndex < _navSteps.length
          ? (_navSteps[_navStepIndex].instruction as String? ??
              getTranslated(context, 'nav.continue'))
          : contToDest;

      _navNext = (_navStepIndex + 1) < _navSteps.length
          ? (_navSteps[_navStepIndex + 1].instruction as String? ??
              getTranslated(context, 'nav.continue'))
          : null;
    }
  }

  Future<void> _expandSheetForTyping() async {
    try {
      await _homeSheetCtrl.animateTo(
        0.88,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  Future<void> _collapseSheetForRoute({double size = 0.24}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 60));
    try {
      await _homeSheetCtrl.animateTo(
        size,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  void _endTrip() async {
    // Stop background session (but do not call this in dispose)
    await _bgNav.stop();
    _uiNavSub?.cancel();
    _uiNavSub = null;

    _predictTimer?.cancel();
    _predictTimer = null;

    // finalize history if started
    if (_activeTripId != null && _tripStartAt != null) {
      final duration = DateTime.now().difference(_tripStartAt!).inSeconds;
      await _travelSvc.finishTrip(
        entryId: _activeTripId!,
        distanceMeters: _tripDistance,
        durationSeconds: duration,
        finishedAt: DateTime.now(),
      );
    }

    setState(() {
      _navigating = false;
      _followEnabled = true;
      _navPolyline = null;
      _navPoints.clear();
      _navDestination = null;
      _navRemainingMeters = 0;
      _navSpeedMps = 0;

      _activeTripId = null;
      _tripStartAt = null;
      _tripDistance = 0;
      _lastNavPoint = null;

      _navSteps = [];
      _navStepIndex = 0;
      _navNow = null;
      _navNext = null;
      _trafficEnabled = false;

      _userArrowMarker = null;

      // Reset metro helpers
      _nearDestSince = null;
      _nearFinalSince = null;
      _metroLeg = 0;
      _nearNextSince = null;
      _nextMinDist = double.infinity;
    });
  }

  // Car ETA (old behavior preserved)
  double _etaSecondsCar() {
    final s = (_navSpeedMps.isFinite && _navSpeedMps > 0.8)
        ? _navSpeedMps
        : (_lastFixSpeed.isFinite && _lastFixSpeed > 0.8
            ? _lastFixSpeed
            : 8.33);
    return (_navRemainingMeters.isFinite && s > 0)
        ? (_navRemainingMeters / s)
        : 0;
  }

// Master ETA used by the UI everywhere
  double _etaSecondsForUI() {
    if (_tripMode == _TripMode.metro) {
      return _etaSecondsMetro(uiPos: _lastFixLL ?? _lastNavPoint);
    }
    return _etaSecondsCar();
  }

  double _etaSecondsMetro({LatLng? uiPos}) {
    // Fallback to car-style if we don't have route/sequence context
    if (_metroSeq.length < 2 || _lastChosenRoute == null) {
      return _etaSecondsCar();
    }

    final pos = uiPos ?? _lastFixLL ?? _metroSeq[_metroLeg].pos;
    final int leg = _metroLeg.clamp(0, _metroSeq.length - 2);

    double secs = 0;

    // --- current leg: remaining run to NEXT station ---
    final StationNode a = _metroSeq[leg];
    final StationNode b = _metroSeq[leg + 1];
    final legPoly = _slicePolylineByStations(a.lineKey, a.index, b.index);
    final remOnLeg = _remainingOnLegMeters(pos, legPoly);
    secs += remOnLeg / _METRO_CRUISE_MPS; // running time to next
    secs += _DWELL_SECS; // dwell at next station

    // --- remaining legs after the next (full inter-station runs) ---
    for (int i = leg + 1; i < _metroSeq.length - 1; i++) {
      final sA = _metroSeq[i];
      final sB = _metroSeq[i + 1];
      final poly = _slicePolylineByStations(sA.lineKey, sA.index, sB.index);
      final dist = _polylineLengthMeters(poly);
      secs += dist / _METRO_CRUISE_MPS; // run time
      secs += _DWELL_SECS; // dwell at each intermediate station
    }

    // --- add planned transfer/walk/last-mile times from the chosen route ---
    // We only add transfer/walk (not metro edges) to avoid double-counting.
    final edges = _lastChosenRoute!.edgesInOrder;
    final ids = _lastChosenRoute!.nodeIds;

    // edge index right AFTER our "next" station
    final String nextId = _metroSeq[leg + 1].id;
    int startEdge = 0;
    for (int i = 0; i < ids.length - 1; i++) {
      if (ids[i + 1] == nextId) {
        startEdge = i + 1;
        break;
      }
    }

    for (int i = startEdge; i < edges.length; i++) {
      final e = edges[i];
      if (e.kind == 'transfer' || e.kind == 'walk') {
        // e.seconds was computed when the route was planned (graph/directions)
        secs += (e.seconds.isFinite ? e.seconds : 0);
      }
    }

    // stability: never negative
    if (!secs.isFinite || secs < 0) secs = 0;
    return secs;
  }

  static double _distMeters(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
        a.latitude, a.longitude, b.latitude, b.longitude);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLocalNotifications.init(); // safe to call multiple times
    _graph = MetroGraph();

    _originCtrl.text = '...';
    _destCtrl.text = '';
    _originCtrl.addListener(() {
      final t = _originCtrl.text.trim();
      if (t.isEmpty) {
        // Clear the drawn route but keep the chosen destination pin (if any)
        _clearPlannedTrip(keepDestMarker: true);
      }
    });

    _destCtrl.addListener(() {
      final t = _destCtrl.text.trim();
      if (t.isEmpty) {
        // Clear the drawn route AND remove destination
        _clearPlannedTrip();
      }
    });

    _originFocus.addListener(() {
      if (_originFocus.hasFocus) {
        setState(() => _active = _ActiveField.origin);
        _expandSheetForTyping();
      }
    });
    _destFocus.addListener(() {
      if (_destFocus.hasFocus) {
        setState(() => _active = _ActiveField.destination);
        _expandSheetForTyping();
      }
    });

    _initLocationAndCenter();
    _prepareDestinationIcon();
    _listenFavorites();

    // ⤵️ If a background nav session is already active, reattach UI
    if (_bgNav.isActive) {
      setState(() {
        _navigating = true;
        _navDestination = _bgNav.currentDestination; // getter in NavSession
      });
      _attachNavStream();
    }
  }

  void _listenFavorites() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _favRef = _db.ref('App/Favorites/$uid');
    _favSub = _favRef!.onValue.listen((event) {
      final data = event.snapshot.value;
      final list = <FavoritePlace>[];
      if (data is Map) {
        data.forEach((key, val) {
          if (val is Map) {
            list.add(FavoritePlace.fromMap(
                key as String, Map<Object?, Object?>.from(val)));
          }
        });
      }
      setState(() => _favorites = list);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _homeSheetCtrl.dispose();
    _originFocus.dispose();
    _destFocus.dispose();
    _debounce?.cancel();

    // ⤵️ Only detach UI listener; keep background nav alive
    _uiNavSub?.cancel();
    _navSub?.cancel(); // safe if unused after migration
    _favSub?.cancel();
    _predictTimer?.cancel();

    super.dispose();
  }

  Future<bool> _guardMetroHours() async {
    final now = DateTime.now();
    if (!MetroHours.isOpen(now)) {
      await showMetroClosedSheet(context, now);
      return false;
    }
    return true;
  }

  // ---------------- Map overlays ----------------
  Set<Circle> _metroStationCircles() {
    int circleId = 0;
    Set<Circle> gen(List<Map<String, dynamic>> stations, Color color) =>
        stations.map((s) {
          return Circle(
            circleId: CircleId('circle_${circleId++}'),
            center: LatLng(s['lat'], s['lng']),
            radius: 30,
            fillColor: color.withOpacity(0.7),
            strokeColor: color,
            strokeWidth: 7,
            zIndex: 1,
          );
        }).toSet();

    bool enabled(String key) =>
        _selectedLineKey == null || _selectedLineKey == key;
    final Set<Circle> result = {};
    if (enabled('blue')) {
      result.addAll(gen(metro.blueStations, metroLineColors['blue']!));
    }
    if (enabled('red')) {
      result.addAll(gen(metro.redStations, metroLineColors['red']!));
    }
    if (enabled('green')) {
      result.addAll(gen(metro.greenStations, metroLineColors['green']!));
    }
    if (enabled('purple')) {
      result.addAll(gen(metro.purpleStations, metroLineColors['purple']!));
    }
    if (enabled('yellow')) {
      result.addAll(gen(metro.yellowStations, metroLineColors['yellow']!));
    }
    if (enabled('orange')) {
      result.addAll(gen(metro.orangeStations, metroLineColors['orange']!));
    }
    result.addAll(_highlightCircles);
    return result;
  }

  Set<Polyline> _thinAllLinePolys() {
    final set = <Polyline>{};
    metroPolys.metroLineCoords.forEach((key, coords) {
      if (coords.isEmpty) return;
      set.add(Polyline(
        polylineId: PolylineId('thin_$key'),
        color: (metroLineColors[key] ?? Colors.grey).withOpacity(0.55),
        width: 4,
        points: coords,
      ));
    });
    return set;
  }

  Set<Polyline> _currentPolylines() {
    final nav = _navPolyline != null ? {_navPolyline!} : <Polyline>{};
    if (_routePolylines.isNotEmpty || _showAllLinesUnderRoute) {
      final base = _showAllLinesUnderRoute ? _thinAllLinePolys() : <Polyline>{};
      return {...base, ..._routePolylines, ...nav};
    }
    return {..._thinAllLinePolys(), ...nav};
  }

  Set<Marker> _stationMarkersForMap() => {..._routeMarkers};

  // ---------------- Location init ----------------
  Future<void> _initLocationAndCenter() async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _notify(getTranslated(
              context, 'Location services are disabled. Please enable GPS.'));
        });
        setState(() {
          _checkingLocation = false;
          _locationGranted = false;
        });
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _notify(getTranslated(context,
              'Location permission permanently denied. Enable it in Settings.'));
        });
        setState(() {
          _checkingLocation = false;
          _locationGranted = false;
        });
        return;
      }
      if (perm == LocationPermission.denied) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _notify(getTranslated(context, 'Location permission denied.'));
        });
        setState(() {
          _checkingLocation = false;
          _locationGranted = false;
        });
        return;
      }

      setState(() => _locationGranted = true);

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      _lastKnownPosition = pos;
      final target = LatLng(pos.latitude, pos.longitude);
      final camera = CameraPosition(target: target, zoom: 15.0);

      _userOrigin = target;
      if (mounted) {
        final label = await _labelForLatLng(target);
        _originCtrl.text = label;
      }

      if (_mapController.isCompleted) {
        final ctrl = await _mapController.future;
        await ctrl.animateCamera(CameraUpdate.newCameraPosition(camera));
      } else {
        _camera = camera;
      }
      setState(() {
        _initialCentered = true;
        _checkingLocation = false;
      });
    } catch (_) {
      setState(() => _checkingLocation = false);
    }
  }

  // ===== Search flow =====
  void _onQueryChanged(String q) {
    _places.startSession();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (q.trim().isEmpty) {
        setState(() => _suggestions = []);
        return;
      }
      _expandSheetForTyping();

      final bias = _lastKnownPosition == null
          ? _lastCameraTarget
          : LatLng(_lastKnownPosition!.latitude, _lastKnownPosition!.longitude);

      // Places API suggestions
      final placeList = await _places.autocomplete(input: q, biasCenter: bias);

      // Favorite matches (by label or address)
      final favMatches = _favorites.where((f) {
        final qq = q.toLowerCase();
        return f.label.toLowerCase().contains(qq) ||
            f.address.toLowerCase().contains(qq);
      }).toList()
        ..sort(
            (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

      // Compose mixed list: favorites first, then places
      final mixed = <_Suggest>[
        ...favMatches.map((f) => _Suggest.fav(f)),
        ...placeList.map((p) => _Suggest.place(p)),
      ];

      if (!mounted) return;
      setState(() => _suggestions = mixed);
    });
  }

  Future<void> _onSuggestionTapPlace(PlaceSuggestion s) async {
    final ll = await _places.detailsLatLng(placeId: s.placeId);
    _places.endSession();
    if (ll == null) return;

    setState(() => _suggestions = []);

    if (_active == _ActiveField.origin) {
      _userOrigin = ll;
      _originCtrl.text = s.title;
      await _tryRouteIfBothReady();
    } else {
      _userDestination = ll;
      _destCtrl.text = s.title;
      _lastDestLabel = s.title;
      _clearRouteOverlays();
      _clearDestinationMarker();
      _setDestinationMarker(ll, label: s.title);
      await _tryRouteIfBothReady();
    }
  }

  Future<void> _onSuggestionTapFavorite(FavoritePlace f) async {
    setState(() => _suggestions = []);
    final ll = LatLng(f.lat, f.lng);
    if (_active == _ActiveField.origin) {
      _userOrigin = ll;
      _originCtrl.text = f.label;
      await _tryRouteIfBothReady();
    } else {
      _userDestination = ll;
      _destCtrl.text = f.label;
      _lastDestLabel = f.label;
      _clearRouteOverlays();
      _clearDestinationMarker();
      _setDestinationMarker(ll, label: f.label);
      await _tryRouteIfBothReady();
    }
  }

  Future<void> _onOriginSubmitted(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;

    if (_suggestions.isNotEmpty && _suggestions.first.kind == 'favorite') {
      await _onSuggestionTapFavorite(_suggestions.first.fav!);
      return;
    }

    final bias = _lastKnownPosition == null
        ? _lastCameraTarget
        : LatLng(_lastKnownPosition!.latitude, _lastKnownPosition!.longitude);
    final res = await _places.textSearchFirst(query: q, near: bias);
    if (res.latLng != null) {
      _userOrigin = res.latLng;
      _originCtrl.text = res.label ?? q;
      await _tryRouteIfBothReady();
    }
  }

  Future<void> _onDestSubmitted(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;
    _clearRouteOverlays();
    _clearDestinationMarker();

    if (_suggestions.isNotEmpty) {
      final first = _suggestions.first;
      if (first.kind == 'favorite') {
        await _onSuggestionTapFavorite(first.fav!);
        return;
      } else {
        await _onSuggestionTapPlace(first.place!);
        return;
      }
    }

    final bias = _lastKnownPosition == null
        ? _lastCameraTarget
        : LatLng(_lastKnownPosition!.latitude, _lastKnownPosition!.longitude);
    final res = await _places.textSearchFirst(query: q, near: bias);
    if (res.latLng != null) {
      _userDestination = res.latLng;
      _destCtrl.text = res.label ?? q;
      _lastDestLabel = res.label ?? q;
      _setDestinationMarker(res.latLng!, label: res.label ?? q);
      await _tryRouteIfBothReady();
    }
  }

  Future<void> _tryRouteIfBothReady() async {
    await _collapseSheetForRoute(size: 0.24);

    final originLL = _userOrigin ??
        (_lastKnownPosition != null
            ? LatLng(
                _lastKnownPosition!.latitude, _lastKnownPosition!.longitude)
            : _lastCameraTarget);
    final destLL = _userDestination;
    if (destLL == null) return;

    // DRIVING: draw car routes and return
    if (_tripMode == _TripMode.drive) {
      _lastDestLabel = _destCtrl.text;
      await _renderDrivingRoute(originLL, destLL);
      setState(() => _lastChosenRoute = null);
      return;
    }

    // METRO: normal flow
    if (!await _guardMetroHours()) return;

    if (_graph.minDistanceToAnyStation(destLL) >
        MetroGraph.maxDestFromStationMeters) {
      _notify(getTranslated(context,
          'That place is outside the metro area (>10 km from nearest station).'));
      return;
    }

    final options = _planRoutes(originLL, destLL);
    if (options.isEmpty) {
      _notify(getTranslated(context,
          'No route found with sensible transfers. Try another destination.'));
      return;
    }

    _lastRouteOptions = options;
    _lastDestLabel = _destCtrl.text;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => RouteOptionsSheet(
        options: options,
        destLabel: _lastDestLabel ?? '',
        cap: _cap,
        onPick: (r) async {
          if (!await _guardMetroHours()) return;
          Navigator.of(ctx).pop();
          _lastChosenRoute = r;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(child: CircularProgressIndicator()),
          );
          await _renderRouteOnMap(r);
          if (mounted) Navigator.of(context).pop();
          await _showTripPreviewForRoute(r, _lastDestLabel ?? '');
        },
      ),
    );
  }

  // ===== DRIVING route renderer (NEW) =====
  Future<void> _renderDrivingRoute(LatLng origin, LatLng dest) async {
    setState(() {
      _routePolylines.clear();
      _routeMarkers.clear();
      _showAllLinesUnderRoute = false;
      _selectedLineKey = null;

      _driveAlternates = null;
      _drivePick = 0;
      _navSteps = [];
      _navStepIndex = 0;
      _navNow = null;
      _navNext = null;
      _trafficEnabled = false; // enable after we actually have a route
    });

    final alts = await _dirs.computeDriveAlternatives(
      origin,
      dest,
      languageCode: Localizations.localeOf(context).languageCode,
    );

    if (alts.isEmpty) {
      // Fallback: routeViaRoads polyline + neutral banner state
      final fb =
          await _dirs.routeViaRoads(origin, dest, mode: TravelMode.drive);
      setState(() {
        _routePolylines = {
          Polyline(
            polylineId: const PolylineId('drive_fb'),
            color: Colors.black87,
            width: 6,
            points: fb?.points ?? [origin, dest],
            zIndex: 1200,
          ),
        };
        _routeMarkers = _driveMarkers(origin, dest);
        _trafficEnabled = true;

        // Seed a sensible banner in fallback (no detailed steps)
        _navSteps = [];
        _navStepIndex = 0;
        _navNow = getTranslated(context, 'Head to route');
        _navNext = null;
      });
      await _fitCameraToRoute();
      return;
    }

    _driveAlternates = alts;

    _drawDrivePolylines();

    setState(() {
      _routeMarkers = _driveMarkers(origin, dest);
    });

    await _fitCameraToRoute();

    // Enable traffic layer and seed banner/steps from the selected route
    setState(() {
      _trafficEnabled = true;
    });
    _onPickDrive(
        _drivePick); // sets _navSteps/_navNow/_navNext and rebuilds ETA badges
  }

  void _drawDrivePolylines() {
    if (_driveAlternates == null || _driveAlternates!.isEmpty) return;

    final set = <Polyline>{};

    for (int i = 0; i < _driveAlternates!.length; i++) {
      final r = _driveAlternates![i];

      // Non-selected (thin neutral)
      if (i != _drivePick) {
        set.add(Polyline(
          polylineId: PolylineId('drive_alt_$i'),
          color: Colors.blueGrey.shade400,
          width: 4,
          points: r.points,
          zIndex: 700,
          consumeTapEvents: true,
          onTap: () => _onPickDrive(i), // ← tap to choose
        ));
        continue;
      }

      // Selected route underlay
      set.add(Polyline(
        polylineId: PolylineId('drive_under_$i'),
        color: Colors.blueGrey.shade300.withOpacity(0.6),
        width: 6,
        points: r.points,
        zIndex: 900,
        consumeTapEvents: true,
        onTap: () => _onPickDrive(i),
      ));

      // Traffic segments (selected)
      if (r.traffic.isNotEmpty) {
        int lastIdx = 0;
        Color segColor(String? s) {
          final t = (s ?? '').toUpperCase();
          if (t.contains('JAM')) return Colors.red;
          if (t.contains('SLOW')) return Colors.orange;
          return Colors.blue; // FREE_FLOW / NORMAL (Google-like cyan/blue)
        }

        for (final seg in r.traffic) {
          final a = seg.startIndex.clamp(0, r.points.length - 1);
          final b = seg.endIndex.clamp(0, r.points.length);
          if (a > lastIdx) {
            set.add(Polyline(
              polylineId: PolylineId('drive_gap_${i}_${lastIdx}_$a'),
              color: segColor('FREE_FLOW'),
              width: 10,
              points: r.points.sublist(lastIdx, a),
              zIndex: 1500,
              consumeTapEvents: true,
              onTap: () => _onPickDrive(i),
            ));
          }
          set.add(Polyline(
            polylineId: PolylineId('drive_tr_${i}_${a}_$b'),
            color: segColor(seg.speed),
            width: 6,
            points: r.points.sublist(a, b),
            zIndex: 1600,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
            consumeTapEvents: true,
            onTap: () => _onPickDrive(i),
          ));
          lastIdx = b;
        }
        if (lastIdx < r.points.length) {
          set.add(Polyline(
            polylineId:
                PolylineId('drive_tail_${i}_${lastIdx}_${r.points.length}'),
            color: Colors.blue,
            width: 6,
            points: r.points.sublist(lastIdx),
            zIndex: 1500,
            consumeTapEvents: true,
            onTap: () => _onPickDrive(i),
          ));
        }
      } else {
        // Fallback coloring with ETA ratio (live vs no-traffic)
        double ratio;
        if (r.staticDurationSeconds > 0) {
          ratio = r.durationSeconds / r.staticDurationSeconds;
        } else {
          // very rare: if static missing, approximate free-flow at ~65 km/h
          final freeFlowSecs = (r.distanceMeters / (65.0 / 3.6)).round();
          ratio = freeFlowSecs > 0 ? r.durationSeconds / freeFlowSecs : 1.0;
        }

        Color trafficColor;
        if (ratio < 1.10) {
          trafficColor = Colors.blue; // free/normal
        } else if (ratio < 1.35) {
          trafficColor = Colors.orange; // slow/moderate
        } else {
          trafficColor = Colors.red; // heavy/jammy
        }

        set.add(Polyline(
          polylineId: PolylineId('drive_main_noint_$i'),
          color: trafficColor,
          width: 6, // a bit thicker for the selected route
          points: r.points,
          zIndex: 1500,
          consumeTapEvents: true,
          onTap: () => _onPickDrive(i),
        ));
      }
    }

    setState(() => _routePolylines = set);
    _rebuildDriveEtaBadges(); // ← create/update inline “21 min” labels
  }

  Set<Marker> _driveMarkers(LatLng origin, LatLng dest) => {
        Marker(
          markerId: const MarkerId('drive_start'),
          position: origin,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: getTranslated(context, 'Start')),
          zIndex: 1200,
        ),
        Marker(
          markerId: const MarkerId('drive_end'),
          position: dest,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
              title: _lastDestLabel ?? getTranslated(context, 'Destination')),
          zIndex: 1200,
        ),
      };

  void _showDriveAlternativesSheet() {
    if (_driveAlternates == null || _driveAlternates!.isNotEmpty == false)
      return;
    final best = _driveAlternates!.first.durationSeconds;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          itemCount: _driveAlternates!.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final r = _driveAlternates![i];
            final delta = r.durationSeconds - best;
            final eta = (r.durationSeconds / 60).round();
            final distKm = (r.distanceMeters / 1000).toStringAsFixed(0);
            return ListTile(
              leading: Icon(i == _drivePick ? Icons.route : Icons.alt_route),
              title: Text('$eta min  •  $distKm km',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: delta > 0
                  ? Text(
                      '+${(delta / 60).round()} ${getTranslated(context, 'min')}',
                      style: const TextStyle(color: Colors.red))
                  : (r.fuelEfficient
                      ? Text(getTranslated(context, 'Saves fuel'),
                          style: const TextStyle(color: Colors.green))
                      : null),
              trailing: i == _drivePick
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : null,
              onTap: () {
                Navigator.of(context).pop();
                setState(() => _drivePick = i);
                _drawDrivePolylines();
              },
            );
          },
        ),
      ),
    );
  }

  // ===== METRO plan/render (unchanged core) =====
  List<RouteOption> _planRoutes(LatLng originLL, LatLng destLL) {
    final adj = {
      for (final e in _graph.baseAdj.entries) e.key: List<GEdge>.from(e.value)
    };

    final origins = _graph.kNearestStations(originLL,
        MetroGraph.originDestCandidates, MetroGraph.maxOriginDestLinkMeters);
    final dests = _graph.kNearestStations(destLL,
        MetroGraph.originDestCandidates, MetroGraph.maxOriginDestLinkMeters);
    if (origins.isEmpty || dests.isEmpty) return [];

    const srcId = 'SRC', dstId = 'DST';
    adj[srcId] = [];
    adj[dstId] = [];

    for (final o in origins) {
      final secs = o.meters / MetroGraph.walkSpeedMps;
      adj[srcId]!.add(
          GEdge(to: o.node.id, seconds: secs, kind: 'walk', meters: o.meters));
    }
    for (final d in dests) {
      final secs = d.meters / MetroGraph.walkSpeedMps;
      (adj[d.node.id] ??= [])
          .add(GEdge(to: dstId, seconds: secs, kind: 'walk', meters: d.meters));
    }

    final nodes = {..._graph.stationMap};
    final results = <RouteOption>[];
    final triedPairs = <String>{};

    for (final o in origins) {
      for (final d in dests) {
        final key = '${o.node.id}->${d.node.id}';
        if (triedPairs.contains(key)) continue;
        triedPairs.add(key);

        final res = _graph.dijkstra(srcId, dstId, adj);
        if (res == null) continue;

        final path = res.path;
        final edges = res.edges;

        double seconds = 0, walkMeters = 0;
        final lineSeq = <String>[];
        String? prevLine;
        for (final e in edges) {
          seconds += e.seconds;
          if (e.kind == 'walk' || e.kind == 'transfer') {
            walkMeters += (e.meters ?? 0);
          }
          if (e.kind == 'metro' && e.lineKey != null) {
            if (prevLine != e.lineKey) {
              prevLine = e.lineKey;
              lineSeq.add(e.lineKey!);
            }
          }
        }
        final transfers = math.max(0, lineSeq.length - 1);

        final opt = RouteOption(
          nodeIds: path,
          nodes: nodes,
          edgesInOrder: edges,
          totalSeconds: seconds,
          walkMeters: walkMeters,
          transfers: transfers,
          lineSequence: lineSeq,
          originLL: originLL,
          destLL: destLL,
        );

        String lastMetroId(List<String> path) {
          for (int i = path.length - 2; i >= 1; i--) {
            final id = path[i];
            if (id.contains(':')) return id;
          }
          return '';
        }

        final sig = '${lineSeq.join(">")}::${lastMetroId(path)}';
        if (!results.any((r) =>
            '${r.lineSequence.join(">")}::${lastMetroId(r.nodeIds)}' == sig)) {
          results.add(opt);
        }

        if (results.length < 3) {
          GEdge? primary;
          for (final e in edges) {
            if (e.kind == 'transfer') {
              if (primary == null || (e.meters ?? 0) > (primary.meters ?? 0)) {
                primary = e;
              }
            }
          }
          if (primary != null) {
            String? removedFrom;
            GEdge? removedEdge;
            adj.forEach((k, list) {
              final ix = list.indexWhere((ee) =>
                  ee.kind == 'transfer' &&
                  ee.to == primary!.to &&
                  (ee.meters ?? 0) == (primary!.meters ?? 0) &&
                  (ee.seconds == primary!.seconds));
              if (ix >= 0) {
                removedFrom = k;
                removedEdge = list.removeAt(ix);
              }
            });

            final res2 = _graph.dijkstra(srcId, dstId, adj);
            if (res2 != null) {
              final p2 = res2.path;
              final e2 = res2.edges;
              double s2 = 0, w2 = 0;
              final ls2 = <String>[];
              String? pl2;
              for (final e in e2) {
                s2 += e.seconds;
                if (e.kind == 'walk' || e.kind == 'transfer') {
                  w2 += (e.meters ?? 0);
                }
                if (e.kind == 'metro' && e.lineKey != null) {
                  if (pl2 != e.lineKey) {
                    pl2 = e.lineKey;
                    ls2.add(e.lineKey!);
                  }
                }
              }
              String lastMetroId2(List<String> path) {
                for (int i = path.length - 2; i >= 1; i--) {
                  final id = path[i];
                  if (id.contains(':')) return id;
                }
                return '';
              }

              final sig2 = '${ls2.join(">")}::${lastMetroId2(p2)}';
              if (!results.any((r) =>
                  '${r.lineSequence.join(">")}::${lastMetroId(r.nodeIds)}' ==
                  sig2)) {
                results.add(RouteOption(
                  nodeIds: p2,
                  nodes: nodes,
                  edgesInOrder: e2,
                  totalSeconds: s2,
                  walkMeters: w2,
                  transfers: math.max(0, ls2.length - 1),
                  lineSequence: ls2,
                  originLL: originLL,
                  destLL: destLL,
                ));
              }
            }
            if (removedFrom != null && removedEdge != null) {
              (adj[removedFrom!] ??= []).add(removedEdge!);
            }
          }
        }
      }
    }

    results.sort((a, b) => a.totalSeconds.compareTo(b.totalSeconds));
    return results.take(3).toList();
  }

  Future<void> _renderRouteOnMap(RouteOption opt) async {
    final walkPattern = <PatternItem>[
      PatternItem.dash(20),
      PatternItem.gap(12)
    ];
    final polys = <Polyline>{};
    final markers = <Marker>{};

    final firstStationId =
        opt.nodeIds.firstWhere((id) => id.contains(':'), orElse: () => '');
    if (firstStationId.isNotEmpty) {
      final firstStation = opt.nodes[firstStationId]!;
      final firstLeg =
          await _dirs.bestFirstLastMile(opt.originLL, firstStation.pos);
      if (firstLeg != null && firstLeg.points.length >= 2) {
        final isDrive = firstLeg.mode == TravelMode.drive;
        polys.add(Polyline(
          polylineId: const PolylineId('firstmile'),
          color: Colors.black87.withOpacity(0.80),
          width: isDrive ? 6 : 4,
          points: firstLeg.points,
          patterns: isDrive ? const <PatternItem>[] : walkPattern,
          zIndex: 1100,
        ));
      } else {
        polys.add(Polyline(
          polylineId: const PolylineId('firstmile_fb'),
          color: Colors.black87.withOpacity(0.55),
          width: 4,
          points: [opt.originLL, firstStation.pos],
          patterns: walkPattern,
          zIndex: 1100,
        ));
      }
      final firstHue = _hueForLineKey(firstStation.lineKey);
      markers.add(Marker(
        markerId: const MarkerId('m_origin_station'),
        position: firstStation.pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(firstHue),
        infoWindow: InfoWindow(
          title: firstStation.name,
          snippet:
              '${getTranslated(context, 'Board')} • ${_cap(firstStation.lineKey)} ${getTranslated(context, 'line')}',
        ),
        zIndex: 1200,
      ));
    }

    String? curLine;
    String? startId;
    for (int i = 0; i < opt.edgesInOrder.length; i++) {
      final e = opt.edgesInOrder[i];
      final fromId = opt.nodeIds[i];
      final toId = opt.nodeIds[i + 1];

      if (e.kind == 'metro') {
        curLine ??= e.lineKey!;
        startId ??= fromId;
        final bool lastOrSwitch = (i == opt.edgesInOrder.length - 1) ||
            (opt.edgesInOrder[i + 1].kind != 'metro') ||
            (opt.edgesInOrder[i + 1].lineKey != curLine);
        if (lastOrSwitch) {
          final a = opt.nodes[startId!]!;
          final b = opt.nodes[toId]!;
          final pts = _slicePolylineByStations(curLine!, a.index, b.index);
          polys.add(Polyline(
            polylineId: PolylineId('metro_${curLine}_${a.index}_${b.index}_$i'),
            color: metroLineColors[curLine] ?? Colors.grey,
            width: 7,
            points: pts,
          ));
          curLine = null;
          startId = null;
        }
      } else if (e.kind == 'transfer') {
        final a = opt.nodes[fromId]!;
        final b = opt.nodes[toId]!;
        final xferLeg =
            await _dirs.routeViaRoads(a.pos, b.pos, mode: TravelMode.walk);
        if (xferLeg != null && xferLeg.points.length >= 2) {
          polys.add(Polyline(
            polylineId: PolylineId('xfer_${a.id}_${b.id}'),
            color: Colors.black87.withOpacity(0.75),
            width: 4,
            points: xferLeg.points,
            patterns: walkPattern,
            zIndex: 1100,
          ));
        } else {
          polys.add(Polyline(
            polylineId: PolylineId('xfer_${a.id}_${b.id}_fb'),
            color: Colors.black87.withOpacity(0.55),
            width: 4,
            points: [a.pos, b.pos],
            patterns: walkPattern,
            zIndex: 1100,
          ));
        }
        final aHue = _hueForLineKey(a.lineKey);
        final bHue = _hueForLineKey(b.lineKey);
        markers.addAll([
          Marker(
            markerId: MarkerId('m_${a.id}'),
            position: a.pos,
            icon: BitmapDescriptor.defaultMarkerWithHue(aHue),
            infoWindow: InfoWindow(
              title: a.name,
              snippet:
                  '${getTranslated(context, 'Transfer from')} ${_cap(a.lineKey)}',
            ),
            zIndex: 1200,
          ),
          Marker(
            markerId: MarkerId('m_${b.id}'),
            position: b.pos,
            icon: BitmapDescriptor.defaultMarkerWithHue(bHue),
            infoWindow: InfoWindow(
              title: b.name,
              snippet: '${getTranslated(context, 'to')} ${_cap(b.lineKey)}',
            ),
            zIndex: 1200,
          ),
        ]);
      }
    }

    final lastStationId = opt.nodeIds.reversed
        .firstWhere((id) => id.contains(':'), orElse: () => '');
    StationNode? lastStation =
        lastStationId.isNotEmpty ? opt.nodes[lastStationId] : null;

    if (lastStation != null) {
      final lastLeg =
          await _dirs.bestFirstLastMile(lastStation.pos, opt.destLL);
      if (lastLeg != null && lastLeg.points.length >= 2) {
        final isDrive = lastLeg.mode == TravelMode.drive;
        polys.add(Polyline(
          polylineId: const PolylineId('lastmile'),
          color: Colors.black87.withOpacity(0.90),
          width: isDrive ? 6 : 4,
          points: lastLeg.points,
          patterns: isDrive ? const <PatternItem>[] : walkPattern,
          zIndex: 1100,
        ));
      } else {
        polys.add(Polyline(
          polylineId: const PolylineId('lastmile_fb'),
          color: Colors.black87.withOpacity(0.55),
          width: 4,
          points: [lastStation.pos, opt.destLL],
          patterns: walkPattern,
          zIndex: 1100,
        ));
      }
      final lastHue = _hueForLineKey(lastStation.lineKey);
      markers.add(Marker(
        markerId: const MarkerId('m_dest_station'),
        position: lastStation.pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(lastHue),
        infoWindow: InfoWindow(
          title: lastStation.name,
          snippet:
              '${getTranslated(context, 'Alight')} • ${_cap(lastStation.lineKey)} ${getTranslated(context, 'line')}',
        ),
        zIndex: 1200,
      ));
    }

    setState(() {
      _routePolylines = polys;
      _routeMarkers = markers;
      _showAllLinesUnderRoute = false;
      _selectedLineKey = null;
    });

    await _fitCameraToRoute();
  }

  Future<void> _fitCameraToRoute() async {
    if (_navigating && !_followEnabled) return; // <— new
    if (!_mapController.isCompleted || _routePolylines.isEmpty) return;
    final pts = <LatLng>[];
    for (final p in _routePolylines) {
      pts.addAll(p.points);
    }
    if (pts.isEmpty) return;
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
    final ctrl = await _mapController.future;
    await ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 56));
  }

  Future<void> _showTripPreviewForRoute(RouteOption r, String destLabel) async {
    await _collapseSheetForRoute(size: 0.22);

    final steps = <String>[];
    final chips = <ModeIcon>[];

    String? currentLine;
    int currentStations = 0;
    String? segStartName;
    void flush(String lastName) {
      if (currentLine != null && currentStations > 0 && segStartName != null) {
        steps.add(
            '${getTranslated(context, 'Ride')} ${_cap(currentLine!)} ${getTranslated(context, 'line')} • ${currentStations + 1} ${getTranslated(context, 'stations')}: $segStartName → $lastName');
        chips.add(ModeIcon(
            icon: Icons.directions_subway_filled,
            label: _cap(currentLine!),
            chipColor: metroLineColors[currentLine!]));
      }
      currentLine = null;
      currentStations = 0;
      segStartName = null;
    }

    for (int i = 0; i < r.edgesInOrder.length; i++) {
      final e = r.edgesInOrder[i];
      final fromId = r.nodeIds[i];
      final toId = r.nodeIds[i + 1];

      if (e.kind == 'walk' && fromId == 'SRC') {
        final firstStation = r.nodes[toId]!;
        steps.add(
            '${getTranslated(context, 'Walk/Drive')} ~${fmtMeters(e.meters ?? 0)} ${getTranslated(context, 'to')} ${firstStation.name} (${_cap(firstStation.lineKey)} ${getTranslated(context, 'line')})');
        chips.add(ModeIcon(
            icon: Icons.directions_walk,
            label: getTranslated(context, 'Walk/Car')));
        continue;
      }

      if (e.kind == 'metro') {
        if (currentLine == null) {
          currentLine = e.lineKey!;
          segStartName = r.nodes[fromId]!.name;
          currentStations = 1;
        } else if (currentLine == e.lineKey) {
          currentStations += 1;
        } else {
          flush(r.nodes[fromId]!.name);
          currentLine = e.lineKey!;
          segStartName = r.nodes[fromId]!.name;
          currentStations = 1;
        }
        continue;
      }

      if (e.kind == 'transfer') {
        flush(r.nodes[fromId]!.name);
        final to = r.nodes[toId]!;
        steps.add(
            '${getTranslated(context, 'Transfer walk')} ~${fmtMeters(e.meters ?? 0)} ${getTranslated(context, 'to')} ${to.name} (${_cap(to.lineKey)} ${getTranslated(context, 'line')})');
        chips.add(ModeIcon(
            icon: Icons.swap_horiz_rounded,
            label: getTranslated(context, 'Transfer')));
        continue;
      }

      if (e.kind == 'walk' && toId == 'DST') {
        final lastStationId = r.nodeIds.reversed
            .firstWhere((id) => id.contains(':'), orElse: () => '');
        if (lastStationId.isNotEmpty) {
          flush(r.nodes[lastStationId]!.name);
        }
        steps.add(
            '${getTranslated(context, 'Walk/Drive')} ~${fmtMeters(e.meters ?? 0)} ${getTranslated(context, 'to')} ${getTranslated(context, 'destination')}');
        chips.add(ModeIcon(
            icon: Icons.directions_walk,
            label: getTranslated(context, 'Walk/Car')));
      }
    }

    final start = DateTime.now();
    final arrival = start.add(Duration(seconds: r.totalSeconds.round()));

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => TripPreviewSheet(
        title: '${getTranslated(context, 'To')} ${_lastDestLabel ?? ''}',
        fromLabel: getTranslated(context, 'From my location'),
        start: start,
        arrival: arrival,
        modeIcons: chips,
        steps: steps,
      ),
    );
  }

  // --------------- misc ---------------
  void _clearRouteOverlays() {
    setState(() {
      _routePolylines.clear();
      _routeMarkers.clear();
      _showAllLinesUnderRoute = false;
      if (_tripMode != _TripMode.drive) _trafficEnabled = false;
    });
  }

  Future<void> _openDiscoverPlaces() async {
    final LatLng? here = _lastKnownPosition == null
        ? null
        : LatLng(_lastKnownPosition!.latitude, _lastKnownPosition!.longitude);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DiscoverPlacesScreen(
        currentLocation: here,
        onPickDestination: (dest, name) async {
          _clearDestinationMarker();
          _setDestinationMarker(dest, label: name);
          _userDestination = dest;
          _lastDestLabel = name;
          await _goTo(dest, title: name, color: Colors.black87);
          Navigator.of(context).pop();
        },
      ),
    ));
  }

  Future<void> _openLinePicker() async {
    final entries = <Map<String, dynamic>>[
      {
        'key': null,
        'name': getTranslated(context, 'All lines'),
        'color': Colors.black87
      },
      {
        'key': 'blue',
        'name': getTranslated(context, 'Blue'),
        'color': metroLineColors['blue']
      },
      {
        'key': 'red',
        'name': getTranslated(context, 'Red'),
        'color': metroLineColors['red']
      },
      {
        'key': 'green',
        'name': getTranslated(context, 'Green'),
        'color': metroLineColors['green']
      },
      {
        'key': 'orange',
        'name': getTranslated(context, 'Orange'),
        'color': metroLineColors['orange']
      },
      {
        'key': 'purple',
        'name': getTranslated(context, 'Purple'),
        'color': metroLineColors['purple']
      },
      {
        'key': 'yellow',
        'name': getTranslated(context, 'Yellow'),
        'color': metroLineColors['yellow']
      },
    ];

    final Map<String, dynamic>? choice =
        await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) {
        final current = _selectedLineKey;
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(100))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(getTranslated(context, 'Choose a metro line'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: entries.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final e = entries[i];
                  final String? key = e['key'];
                  final bool selected =
                      key == current || (key == null && current == null);
                  final Color dot = (e['color'] as Color?) ?? Colors.black87;
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: dot, radius: 12),
                    title: Text(e['name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: selected
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    onTap: () => Navigator.of(context).pop(e),
                  );
                },
              ),
            ),
          ]),
        );
      },
    );

    if (choice == null) return;

    // All lines → just reset to previous behavior
    final String? key = choice['key'] as String?;
    if (key == null) {
      setState(() => _selectedLineKey = null);
      _updateStationMarkersForLine(null);
      _notify(getTranslated(context, 'Showing all lines'));
      return;
    }

    // For a specific line, open the new segment picker
    final stations = _stationsFor(key);
    setState(() => _selectedLineKey = key);
    _updateStationMarkersForLine(key);

    final res = await Navigator.of(context).push<LineSegmentResult>(
      MaterialPageRoute(
        builder: (_) => LineSegmentPickerScreen(
          lineKey: key,
          stations: stations,
        ),
      ),
    );

    if (res != null) {
      await _drawLineSegment(key, res.fromIndex, res.toIndex);
      _notify('${getTranslated(context, 'Segment')}: '
          '${stations[res.fromIndex]['name']} → ${stations[res.toIndex]['name']}');
    } else {
      // no segment chosen; keep just the line markers visible
      _notify(
          '${getTranslated(context, 'Showing')} ${_cap(key)} ${getTranslated(context, 'line')}');
    }
  }

  Future<void> _drawLineSegment(
      String lineKey, int fromIndex, int toIndex) async {
    // ensure indices in natural order for slicing
    final int a = math.min(fromIndex, toIndex);
    final int b = math.max(fromIndex, toIndex);

    final pts = _slicePolylineByStations(lineKey, a, b);
    if (pts.length < 2) return;

    final color = metroLineColors[lineKey] ?? Colors.black87;

    setState(() {
      // show thin base network under the chosen segment
      _showAllLinesUnderRoute = true;
      _selectedLineKey = lineKey;

      _routePolylines = {
        Polyline(
          polylineId: PolylineId('seg_${lineKey}_$a\_$b'),
          color: color,
          width: 6,
          points: pts,
          zIndex: 1400,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      };

      // optional: show station markers for that line
      _updateStationMarkersForLine(lineKey);
    });

    await _fitCameraToRoute();
  }

  void _updateStationMarkersForLine(String? key) {
    if (key == null) {
      setState(() => _stationMarkers.clear());
      return;
    }
    final stations = _stationsFor(key);
    final color = metroLineColors[key] ?? Colors.black87;
    final hue = _hueForColor(color);
    final markers = <Marker>{};
    for (int i = 0; i < stations.length; i++) {
      final s = stations[i];
      markers.add(Marker(
        markerId: MarkerId('st_${key}_$i'),
        position: LatLng(s['lat'], s['lng']),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: InfoWindow(
            title: s['name'] as String,
            snippet:
                '${_cap(key)} ${getTranslated(context, 'line')} • #${i + 1}'),
        zIndex: 1000,
      ));
    }
    setState(() => _stationMarkers = markers);
  }

  List<Map<String, dynamic>> _stationsFor(String key) {
    switch (key) {
      case 'blue':
        return metro.blueStations;
      case 'red':
        return metro.redStations;
      case 'green':
        return metro.greenStations;
      case 'orange':
        return metro.orangeStations;
      case 'purple':
        return metro.purpleStations;
      case 'yellow':
        return metro.yellowStations;
      default:
        return const [];
    }
  }

  String _cap(String key) =>
      key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);

  Future<void> _goTo(LatLng target,
      {required String title, required Color color}) async {
    final ctrl = await _mapController.future;
    await ctrl.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 16.5)));
    _setHighlight(target, color: color);
    _notify('${getTranslated(context, 'Centered on')} $title');
  }

  void _setHighlight(LatLng center, {required Color color}) {
    setState(() {
      _highlightCircles = {
        Circle(
          circleId: const CircleId('search_highlight'),
          center: center,
          radius: 85,
          fillColor: color.withOpacity(0.20),
          strokeColor: Colors.white,
          strokeWidth: 3,
          zIndex: 999,
        ),
      };
    });
  }

  Future<void> _setOriginHere() async {
    _userOrigin = _lastCameraTarget;
    final label = await _labelForLatLng(_lastCameraTarget);
    _originCtrl.text = label;
    _notify(getTranslated(context, 'Origin set to map center.'));
    await _tryRouteIfBothReady();
  }

  Future<String> _labelForLatLng(LatLng ll) async {
    try {
      // Prefer a Places/Geocoding reverse lookup
      final String? addr = await _places
          .reverseGeocode(ll); // <-- implement in PlacesService if not already
      if (addr != null && addr.trim().isNotEmpty) return addr.trim();

      // Fallback: short lat/lng string
      return '${ll.latitude.toStringAsFixed(5)}, ${ll.longitude.toStringAsFixed(5)}';
    } catch (_) {
      return '${ll.latitude.toStringAsFixed(5)}, ${ll.longitude.toStringAsFixed(5)}';
    }
  }

  void _notify(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  List<LatLng> _slicePolylineByStations(
      String lineKey, int fromIndex, int toIndex) {
    final pts = metroPolys.metroLineCoords[lineKey];
    if (pts == null || pts.isEmpty) return const [];
    final stations = _stationsFor(lineKey);
    int clampIdx(int i) => i.clamp(0, stations.length - 1);
    final sFrom = stations[clampIdx(fromIndex)];
    final sTo = stations[clampIdx(toIndex)];
    final fromLatLng = LatLng(sFrom['lat'] as double, sFrom['lng'] as double);
    final toLatLng = LatLng(sTo['lat'] as double, sTo['lng'] as double);
    int nearestIndex(List<LatLng> poly, LatLng t) {
      int bestIdx = 0;
      double best = double.infinity;
      for (int i = 0; i < poly.length; i++) {
        final p = poly[i];
        final d = dist2(p, t);
        if (d < best) {
          best = d;
          bestIdx = i;
        }
      }
      return bestIdx;
    }

    final iA = nearestIndex(pts, fromLatLng);
    final iB = nearestIndex(pts, toLatLng);
    final start = math.min(iA, iB);
    final end = math.max(iA, iB);
    return pts.sublist(start, end + 1);
  }

  double _hueForColor(Color c) {
    if (c == Colors.blue || c.value == (metroLineColors['blue']?.value ?? 0)) {
      return BitmapDescriptor.hueBlue;
    }
    if (c == Colors.red || c.value == (metroLineColors['red']?.value ?? 0)) {
      return BitmapDescriptor.hueRed;
    }
    if (c == Colors.green ||
        c.value == (metroLineColors['green']?.value ?? 0)) {
      return BitmapDescriptor.hueGreen;
    }
    if (c == Colors.orange ||
        c.value == (metroLineColors['orange']?.value ?? 0)) {
      return BitmapDescriptor.hueOrange;
    }
    if (c == Colors.purple ||
        c.value == (metroLineColors['purple']?.value ?? 0)) {
      return BitmapDescriptor.hueViolet;
    }
    if (c == Colors.amber ||
        c.value == (metroLineColors['yellow']?.value ?? 0)) {
      return BitmapDescriptor.hueYellow;
    }
    return BitmapDescriptor.hueAzure;
  }

  double _hueForLineKey(String key) {
    final c = metroLineColors[key] ?? Colors.blueGrey;
    return _hueForColor(c);
  }

  void _showUpcomingStopsOnCurrentLine() {
    if (_metroSeq.length < 2 || _metroCurLineKey == null) return;

    // Collect next stops on the CURRENT line only, until transfer/end
    final String curLine = _metroCurLineKey!;
    final stops = <({String name, bool isTransfer})>[];

    // Start from the next station of the current leg
    for (int i = _metroLeg + 1; i < _metroSeq.length; i++) {
      final prev = _metroSeq[i - 1];
      final st = _metroSeq[i];

      // If the previous hop wasn't on the same line anymore, we’re past the segment
      if (prev.lineKey != curLine) break;

      // A transfer **after** this station happens if the next hop switches lines
      bool transferAfterThis = false;
      if (i + 1 < _metroSeq.length) {
        final here = _metroSeq[i];
        final next = _metroSeq[i + 1];
        transferAfterThis = (here.lineKey != next.lineKey);
      }

      stops.add((name: st.name, isTransfer: transferAfterThis));

      // If we’ll transfer after this stop, stop listing here
      if (transferAfterThis) break;
    }

    if (stops.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${getTranslated(context, "Upcoming on")} ${_cap(curLine)} ${getTranslated(context, "line")}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemCount: stops.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final s = stops[i];
                  return ListTile(
                    leading: const Icon(Icons.directions_subway_filled),
                    title: Text(
                      s.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: s.isTransfer
                        ? Text(
                            getTranslated(context, 'Transfer here'),
                            style: const TextStyle(color: Colors.orange),
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========= Compact fancy destination marker =========
  Future<void> _prepareDestinationIcon() async {
    final dpr = MediaQueryData.fromWindow(ui.window).devicePixelRatio;
    final logicalW = 28.0, logicalH = 40.0;
    final width = (logicalW * dpr).clamp(28.0, 90.0).round();
    final height = (logicalH * dpr).clamp(40.0, 130.0).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
        recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    final paint = Paint()..isAntiAlias = true;

    final body = Path()
      ..moveTo(width / 2, height.toDouble())
      ..quadraticBezierTo(
          width * 0.08, height * 0.64, width * 0.08, height * 0.36)
      ..arcToPoint(Offset(width * 0.92, height * 0.36),
          radius: Radius.circular(width.toDouble()))
      ..quadraticBezierTo(
          width * 0.92, height * 0.64, width / 2, height.toDouble())
      ..close();
    paint.color = const Color(0xFF5E35B1);
    canvas.drawPath(body, paint);

    paint.color = const Color(0xFF7E57C2).withOpacity(0.6);
    final sheen = Path()
      ..moveTo(width * 0.54, height * 0.98)
      ..quadraticBezierTo(
          width * 0.86, height * 0.62, width * 0.84, height * 0.38)
      ..arcToPoint(Offset(width * 0.70, height * 0.26),
          radius: Radius.circular(width * 0.34))
      ..lineTo(width * 0.54, height * 0.98)
      ..close();
    canvas.drawPath(sheen, paint);

    paint.color = const Color(0xFFFFFFFF);
    canvas.drawCircle(Offset(width / 2, height * 0.34), width * 0.12, paint);
    paint.color = const Color(0xFF212121);
    canvas.drawCircle(Offset(width / 2, height * 0.34), width * 0.035, paint);

    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    setState(() {
      _destIcon = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
    });
  }

  void _setDestinationMarker(LatLng pos, {required String label}) {
    if (_destIcon == null) return;
    final m = Marker(
      markerId: const MarkerId('m_user_destination'),
      position: pos,
      icon: _destIcon!,
      anchor: const Offset(0.5, 1.0),
      infoWindow: InfoWindow(
        title: label,
        snippet: getTranslated(context, 'Chosen destination'),
      ),
      zIndex: 2000,
    );
    setState(() => _destMarker = m);
  }

  void _clearDestinationMarker() {
    if (_destMarker != null) {
      setState(() => _destMarker = null);
    }
  }

  // ===== Formatting helpers for status pill =====
  static String _fmtDist(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

  static String _fmtMins(double secs) {
    final m = (secs / 60).ceil();
    return '$m ${m == 1 ? 'min' : 'min'}';
    // keep 'min' per existing localization
  }

  static String _fmtSpeed(double mps) {
    if (!mps.isFinite || mps <= 0) return '– km/h';
    return '${(mps * 3.6).toStringAsFixed(0)} km/h';
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.kBackGroundColor,
      extendBody: true,
      extendBodyBehindAppBar: true,
      bottomNavigationBar: BottomNav(
        index: 0,
        onChanged: (i) async {
          if (i == 1) {
            await _openLinePicker();
            return;
          }
          if (i == 2) {
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const TicketScreen()));
            return;
          }
          if (i == 3) {
            // Favorites: await result and treat as a picked destination
            final res = await Navigator.of(context).push<FavoritePlace>(
              MaterialPageRoute(builder: (_) => const FavoritesScreen()),
            );
            if (res != null) {
              _clearRouteOverlays();
              _clearDestinationMarker();
              _userDestination = LatLng(res.lat, res.lng);
              _destCtrl.text = res.label;
              _lastDestLabel = res.label;
              _setDestinationMarker(_userDestination!, label: res.label);
              await _tryRouteIfBothReady();
            }
            return;
          }
        },
      ),
      body: Stack(children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: _camera,
            polylines: _currentPolylines(),
            circles: _metroStationCircles(),
            markers: {
              if (_userArrowMarker != null)
                _userArrowMarker!, // <— heading arrow
              ..._stationMarkersForMap(),
              if (_destMarker != null) _destMarker!,
            },
            onCameraMove: (pos) {
              // Only break follow when user changes ZOOM (pinch/double-tap)
              final zoomChanged = (pos.zoom - _camera.zoom).abs() > 0.01;
              if (zoomChanged && _navigating && !_camBusy && _followEnabled) {
                setState(() => _followEnabled = false);
              }

              _lastCameraTarget = pos.target;
              _camera =
                  pos; // keep latest zoom/bearing/tilt for next comparisons
            },
            onCameraMoveStarted: () {
              // Do nothing here; panning/tilting/rotating won't break follow
            },

            onMapCreated: (c) async {
              _mapController.complete(c);
              if (_locationGranted && !_initialCentered) {
                try {
                  final pos = await Geolocator.getCurrentPosition(
                      desiredAccuracy: LocationAccuracy.high);
                  _lastKnownPosition = pos;
                  await c.animateCamera(CameraUpdate.newCameraPosition(
                    CameraPosition(
                        target: LatLng(pos.latitude, pos.longitude),
                        zoom: 15.0),
                  ));
                  setState(() => _initialCentered = true);
                } catch (_) {}
              }
            },
            myLocationEnabled:
                !_navigating, // <— hide default blue dot during nav
            myLocationButtonEnabled: true,
            compassEnabled: true,
            zoomControlsEnabled: false,
            buildingsEnabled: true,
            trafficEnabled: _trafficEnabled,
          ),
        ),

        if (_checkingLocation)
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.transparent),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
          ),

        // profile
        SafeArea(
            child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 8),
            child: CircleAction(
              icon: Icons.person_rounded,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => AccountDrawerScreen(
                        displayName: widget.firstName, appVersion: '1.2.0')),
              ),
            ),
          ),
        )),

        // bell
        SafeArea(
            child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 12, top: 8),
            child: CircleAction(
                icon: Icons.notifications_none_rounded, onTap: () {}),
          ),
        )),

        // ====== NEW: Start Trip / End Trip pill for CAR mode (banner) ======
        if (_navigating && _tripMode == _TripMode.drive)
          // if (_navigating && _tripMode == _TripMode.drive && false)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B5E20), // deep green banner
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                        blurRadius: 8,
                        color: Colors.black26,
                        offset: Offset(0, 2))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _navNow ?? getTranslated(context, 'Head to route'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (_navNext != null)
                      Text(
                        '${getTranslated(context, 'Then')}  $_navNext',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      '${_fmtMins(_etaSecondsForUI())} • ${_fmtDist(_navRemainingMeters)} • ${_fmtSpeed(_navSpeedMps)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ====== Original Metro banner remains for metro mode ======
        if (_navigating && _tripMode == _TripMode.metro)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Builder(
                builder: (ctx) {
                  // Pick banner color by current line; fallback to deep green
                  final Color bannerColor = (_metroCurLineKey != null)
                      ? (metroLineColors[_metroCurLineKey!] ??
                          const Color(0xFF1B5E20))
                      : const Color(0xFF1B5E20);

                  // compute start/arrival BEFORE returning the Container
                  final DateTime startT = _tripStartAt ?? DateTime.now();

// _etaSecondsForUI() may return double — convert to a non-negative int
                  final int etaSecs = ((_etaSecondsForUI() as num).ceil())
                      .clamp(0, 7 * 24 * 3600);

                  final DateTime etaT =
                      DateTime.now().add(Duration(seconds: etaSecs));

                  // Small helper pill
                  Widget _pill(IconData icon, String text, {Color? fg}) =>
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 16, color: fg ?? Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              text,
                              style: TextStyle(
                                color: fg ?? Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      );

                  return Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B5E20),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                            blurRadius: 8,
                            color: Colors.black26,
                            offset: Offset(0, 2))
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        Text(
                          '${getTranslated(context, 'Destination to')} ${_lastDestLabel ?? ''}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Start / Arrival line
                        Text(
                          '${getTranslated(context, "Start")}: ${_fmtClock(startT)} • '
                          '${getTranslated(context, "Arrival")}: ${_fmtClock(etaT)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        4.kH,
                        Text(
                          '${_fmtDist(_navRemainingMeters)} • ${_fmtSpeed(_navSpeedMps)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),

                        // Current line & stops remaining pill
                        if (_metroCurLineKey != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                // Make sure you already added: import 'package:your_app/widgets/metro/onboard_display.dart';

                                InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () async {
                                    if (_metroCurLineKey == null) return;

                                    // 1) Get current location with a safe fallback
                                    Position pos;
                                    try {
                                      pos = await Geolocator.getCurrentPosition(
                                          desiredAccuracy:
                                              LocationAccuracy.high);
                                    } catch (_) {
                                      pos = await Geolocator
                                              .getLastKnownPosition() ??
                                          Position(
                                            latitude: 24.7136,
                                            longitude:
                                                46.6753, // Riyadh center fallback
                                            timestamp: DateTime.now(),
                                            accuracy: 100.0,
                                            altitude: 0.0,
                                            altitudeAccuracy: 0.0,
                                            heading: 0.0,
                                            headingAccuracy: 0.0,
                                            speed: 0.0,
                                            speedAccuracy: 0.0,
                                            isMocked: false,
                                            floor: null,
                                          );
                                    }
                                    final double myLat = pos.latitude;
                                    final double myLng = pos.longitude;

                                    // 2) Color mapper
                                    Color _colorFor(String key) {
                                      switch (key.toLowerCase()) {
                                        case 'blue':
                                          return const Color(0xFF1E88E5);
                                        case 'red':
                                          return const Color(0xFFE53935);
                                        case 'green':
                                          return const Color(0xFF43A047);
                                        case 'yellow':
                                          return const Color(0xFFFDD835);
                                        case 'orange':
                                          return const Color(0xFFFB8C00);
                                        case 'purple':
                                          return const Color(0xFF8E24AA);
                                        default:
                                          return Theme.of(context)
                                              .colorScheme
                                              .primary;
                                      }
                                    }

                                    // 3) Choose station list for current line
                                    final String rawKey = _metroCurLineKey!;
                                    final String keyLower =
                                        rawKey.toLowerCase();
                                    final List<Map<String, dynamic>> rawStops =
                                        switch (keyLower) {
                                      'red' => metro.redStations,
                                      'yellow' => metro.yellowStations,
                                      'purple' => metro.purpleStations,
                                      'blue' => metro.blueStations,
                                      'orange' => metro.orangeStations,
                                      'green' => metro.greenStations,
                                      _ => const <Map<String, dynamic>>[],
                                    };
                                    if (rawStops.isEmpty) return;

                                    // 4) Build a name->lines index (for transfer badges)
                                    final Map<String, List<String>>
                                        nameToLines = {};
                                    void _index(String line,
                                        List<Map<String, dynamic>> list) {
                                      for (final s in list) {
                                        final n = (s['name'] as String).trim();
                                        nameToLines
                                            .putIfAbsent(n, () => <String>[])
                                            .add(line);
                                      }
                                    }

                                    _index('Red', metro.redStations);
                                    _index('Yellow', metro.yellowStations);
                                    _index('Purple', metro.purpleStations);
                                    _index('Blue', metro.blueStations);
                                    _index('Orange', metro.orangeStations);
                                    _index('Green', metro.greenStations);

                                    // 5) Map to MetroStop and keep lat/lng
                                    final enriched = rawStops.map((m) {
                                      final String nameEn = m['name'] as String;
                                      final transfers = List<String>.from(
                                              nameToLines[nameEn] ??
                                                  const <String>[])
                                          .where((l) =>
                                              l.toLowerCase() != keyLower)
                                          .toList();
                                      return (
                                        stop: MetroStop(
                                          id: nameEn,
                                          nameEn: nameEn,
                                          nameAr: m['nameAr'] as String,
                                          isTransfer: transfers.isNotEmpty,
                                          transferLines: transfers,
                                        ),
                                        lat: (m['lat'] as num).toDouble(),
                                        lng: (m['lng'] as num).toDouble(),
                                      );
                                    }).toList();
                                    final List<MetroStop> stops =
                                        enriched.map((e) => e.stop).toList();

                                    // 6) Helpers
                                    double _deg(double v) =>
                                        v * (math.pi / 180.0);
                                    double _haversine(double lat1, double lon1,
                                        double lat2, double lon2) {
                                      const R = 6371000.0;
                                      final dLat = _deg(lat2 - lat1);
                                      final dLon = _deg(lon2 - lon1);
                                      final a = math.sin(dLat / 2) *
                                              math.sin(dLat / 2) +
                                          math.cos(_deg(lat1)) *
                                              math.cos(_deg(lat2)) *
                                              math.sin(dLon / 2) *
                                              math.sin(dLon / 2);
                                      final c = 2 *
                                          math.atan2(
                                              math.sqrt(a), math.sqrt(1 - a));
                                      return R * c;
                                    }

                                    // 7) Nearest station to YOU (currentIdx)
                                    int currentIdx = 0;
                                    double best = double.infinity;
                                    for (int i = 0; i < enriched.length; i++) {
                                      final d = _haversine(myLat, myLng,
                                          enriched[i].lat, enriched[i].lng);
                                      if (d < best) {
                                        best = d;
                                        currentIdx = i;
                                      }
                                    }

                                    // 8) Destination-aware DIRECTION (terminal)
                                    // Replace these with your real destination variables:
                                    final LatLng? _destLL = _tripDestLL ??
                                        _navDestination ??
                                        _userDestination;
                                    final double? destLat = _destLL?.latitude;
                                    final double? destLng = _destLL?.longitude;

                                    bool forward;
                                    if (destLat != null && destLng != null) {
                                      // snap destination to nearest station on this line
                                      int destIdx = 0;
                                      double bestDest = double.infinity;
                                      for (int i = 0;
                                          i < enriched.length;
                                          i++) {
                                        final d = _haversine(destLat, destLng,
                                            enriched[i].lat, enriched[i].lng);
                                        if (d < bestDest) {
                                          bestDest = d;
                                          destIdx = i;
                                        }
                                      }
                                      // move forward if destination is after current in list order
                                      forward = destIdx >= currentIdx;

                                      // if equal, choose closer terminal from current position
                                      if (destIdx == currentIdx) {
                                        final dToFirst = _haversine(
                                            enriched[currentIdx].lat,
                                            enriched[currentIdx].lng,
                                            enriched.first.lat,
                                            enriched.first.lng);
                                        final dToLast = _haversine(
                                            enriched[currentIdx].lat,
                                            enriched[currentIdx].lng,
                                            enriched.last.lat,
                                            enriched.last.lng);
                                        forward = dToLast < dToFirst;
                                      }
                                    } else {
                                      // fallback if no destination set: neighbor-distance heuristic
                                      final prevIdx = (currentIdx - 1)
                                          .clamp(0, stops.length - 1);
                                      final nextIdx = (currentIdx + 1)
                                          .clamp(0, stops.length - 1);
                                      final dPrev = _haversine(
                                          myLat,
                                          myLng,
                                          enriched[prevIdx].lat,
                                          enriched[prevIdx].lng);
                                      final dNext = _haversine(
                                          myLat,
                                          myLng,
                                          enriched[nextIdx].lat,
                                          enriched[nextIdx].lng);
                                      forward = dNext <= dPrev;
                                    }

                                    // 9) Header (terminal) + visuals
                                    final String lineKey = _cap(rawKey);
                                    final Color lineColor = _colorFor(rawKey);
                                    final String dirEn = forward
                                        ? 'To ${stops.last.nameEn}'
                                        : 'To ${stops.first.nameEn}';
                                    final String dirAr = forward
                                        ? 'إلى ${stops.last.nameAr}'
                                        : 'إلى ${stops.first.nameAr}';

                                    await showOnboardDisplay(
                                      context,
                                      stops: stops,
                                      currentIndex: currentIdx,
                                      lineKey: lineKey,
                                      lineColor: lineColor,
                                      directionNameEn: dirEn,
                                      directionNameAr: dirAr,
                                      etaToNext: Duration(
                                        seconds:
                                            (_etaSecondsMetro(uiPos: _lastFixLL)
                                                    as num)
                                                .round(),
                                      ),
                                      isRTL: Localizations.localeOf(context)
                                              .languageCode ==
                                          'ar',
                                      forward: forward,
                                      nextStationOverride:
                                          _metroNextName, // ✅ ensures sync with green banner
                                    );
                                  },
                                  child: _pill(
                                    Icons.directions_subway_filled,
                                    ' ${_cap(_metroCurLineKey!)} ${getTranslated(context, "line")} • '
                                    '$_stopsLeftOnLine ${getTranslated(context, "stations")}',
                                  ),
                                )
                              ],
                            ),
                          ),

                        // Transfer vs Next/After
                        if (_transferAtNext && _transferToLineKey != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              '${getTranslated(context, "Change line here")} → '
                              '${_cap(_transferToLineKey!)} ${getTranslated(context, "line")}',
                              style: const TextStyle(
                                color: Colors.yellowAccent,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                        else ...[
                          if (_metroNextName != null &&
                              _metroNextName!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                '${getTranslated(context, "Next station")}: $_metroNextName',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          else if (_metroSeq.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                '${getTranslated(context, "Head to station")}: ${_metroSeq.first.name}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (_metroAfterName != null &&
                              _metroAfterName!.isNotEmpty &&
                              _metroAfterName != _metroNextName)
                            Text(
                              '${getTranslated(context, "After next station")}: $_metroAfterName',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          if (_metroAlightAtNext)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                getTranslated(
                                    context, 'Alight at next station'),
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        // ───────────────────────── bottom sheet (hidden while navigating) ─────────────────────────
        if (!_navigating)
          DraggableScrollableSheet(
            key: const ValueKey('home_sheet'),
            controller: _homeSheetCtrl,
            initialChildSize: 0.34,
            minChildSize: 0.2,
            maxChildSize: 0.92,
            snap: true,
            builder: (context, controller) {
              final bottomInset = MediaQuery.of(context).viewInsets.bottom;
              return AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: bottomInset),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF6F9F3),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(26)),
                  ),
                  child: ListView(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        getTranslated(context, 'Where to?'),
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),

                      // Origin
                      SearchField(
                        hint: getTranslated(context, 'From (origin)'),
                        controller: _originCtrl,
                        onSubmitted: (s) async {
                          await _onOriginSubmitted(s);
                        },
                        onChanged: (q) {
                          _active = _ActiveField.origin;
                          _onQueryChanged(q);
                        },
                        showClearButton: true,
                        focusNode: _originFocus,
                      ),
                      const SizedBox(height: 10),

                      // Destination
                      SearchField(
                        hint:
                            getTranslated(context, 'Search station or address'),
                        controller: _destCtrl,
                        onSubmitted: (s) async {
                          await _onDestSubmitted(s);
                        },
                        onChanged: (q) {
                          _active = _ActiveField.destination;
                          _onQueryChanged(q);
                        },
                        showClearButton: true,
                        focusNode: _destFocus,
                      ),

                      const SizedBox(height: 8),

                      // Metro / Car selector
                      Row(
                        children: [
                          ChoiceChip(
                            selected: _tripMode == _TripMode.metro,
                            onSelected: (_) => setState(() {
                              _tripMode = _TripMode.metro;
                              _trafficEnabled =
                                  false; // metro: no traffic layer
                            }),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.directions_subway_filled, size: 18),
                                SizedBox(width: 6),
                                Text(getTranslated(context, 'Metro')),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          ChoiceChip(
                            selected: _tripMode == _TripMode.drive,
                            onSelected: (_) => setState(() {
                              _tripMode = _TripMode.drive;
                              // only enable traffic if a route/destination already exists
                              _trafficEnabled = (_userDestination != null) &&
                                  ((_driveAlternates?.isNotEmpty ?? false) ||
                                      _routePolylines.isNotEmpty);
                            }),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.directions_car_rounded, size: 18),
                                SizedBox(width: 6),
                                Text(getTranslated(context, 'Car')),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      if (_lastRouteOptions != null && _lastDestLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.history),
                            label:
                                Text(getTranslated(context, 'Recent Routes')),
                            onPressed: () async {
                              await _collapseSheetForRoute(size: 0.24);
                              await showModalBottomSheet(
                                context: context,
                                isScrollControlled: false,
                                backgroundColor: Colors.white,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(18)),
                                ),
                                builder: (ctx) => RouteOptionsSheet(
                                  options: _lastRouteOptions!,
                                  destLabel: _lastDestLabel!,
                                  cap: _cap,
                                  onPick: (r) async {
                                    if (!await _guardMetroHours()) return;
                                    Navigator.of(ctx).pop();
                                    _lastChosenRoute = r;
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (_) => BusyShimmerDialog(
                                        title: getTranslated(
                                            context, 'Planning route…'),
                                        subtitle: getTranslated(context,
                                            'Finding best transfers and timing'),
                                      ),
                                    );
                                    await _renderRouteOnMap(r);
                                    if (mounted) Navigator.of(context).pop();

                                    await _renderRouteOnMap(r);
                                    if (mounted) Navigator.of(context).pop();
                                    await _showTripPreviewForRoute(
                                        r, _lastDestLabel!);
                                  },
                                ),
                              );
                            },
                          ),
                        ),

                      if (_tripMode == _TripMode.drive &&
                          _driveAlternates != null &&
                          _driveAlternates!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.alt_route_rounded),
                            label:
                                Text(getTranslated(context, 'Driving Routes')),
                            onPressed: () async {
                              await _collapseSheetForRoute(size: 0.24);
                              _showDriveAlternativesSheet();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black87,
                              side: const BorderSide(color: Colors.black12),
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),

                      if (_suggestions.isNotEmpty)
                        LayoutBuilder(
                          builder: (ctx, constraints) {
                            final double maxListHeight = math.min(
                                320, MediaQuery.of(ctx).size.height * 0.45);
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: const [
                                  BoxShadow(
                                      blurRadius: 6,
                                      color: Colors.black12,
                                      offset: Offset(0, 2))
                                ],
                              ),
                              child: ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxHeight: maxListHeight),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  physics: const ClampingScrollPhysics(),
                                  itemCount: _suggestions.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1, thickness: .5),
                                  itemBuilder: (_, i) {
                                    final s = _suggestions[i];
                                    return ListTile(
                                      dense: true,
                                      leading: Icon(s.icon),
                                      title: Text(
                                        s.title,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      subtitle: Text(
                                        s.subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onTap: () async {
                                        if (s.kind == 'place') {
                                          await _onSuggestionTapPlace(s.place!);
                                        } else {
                                          await _onSuggestionTapFavorite(
                                              s.fav!);
                                        }
                                      },
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),

                      const SizedBox(height: 10),

                      SizedBox(
                        height: 40,
                        child: OutlinedButton.icon(
                          onPressed: _openDiscoverPlaces,
                          icon: const Icon(Icons.explore_rounded),
                          label:
                              Text(getTranslated(context, 'Discover places')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black87,
                            side: const BorderSide(color: Colors.black12),
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 16, color: Colors.black54),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              getTranslated(context,
                                  'Tip: set your origin using the map center (tap "Set origin here").'),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black54),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            FilterChipPill(
                              label: getTranslated(context, 'All'),
                              icon: Image.asset('assets/logo/darb_logo.jpeg',
                                  width: 20, height: 20),
                              selected: true,
                              onTap: () {},
                            ),
                            const SizedBox(width: 10),
                            FilterChipPill(
                              label: getTranslated(context, 'Metro'),
                              icon: const Icon(Icons.directions_subway_filled),
                              selected: true,
                              onTap: () {},
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      if (!widget.emailVerified) VerifyBanner(onResend: () {}),
                    ],
                  ),
                ),
              );
            },
          )
        else
          const SizedBox.shrink(),
// ───────────────────────── end bottom sheet ─────────────────────────

        // set origin to map center + Start/End
        Positioned(
          right: 12,
          bottom: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_userDestination != null &&
                  (_lastChosenRoute != null || _tripMode == _TripMode.drive))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FloatingActionButton.extended(
                    heroTag: 'navStart',
                    backgroundColor:
                        _navigating ? Colors.red.shade600 : Colors.green,
                    foregroundColor: Colors.white,
                    onPressed: _navigating ? _endTrip : _startTrip,
                    icon: Icon(_navigating
                        ? Icons.stop_rounded
                        : Icons.directions_rounded),
                    label: Text(_navigating
                        ? getTranslated(context, 'End trip')
                        : getTranslated(context, 'Start trip')),
                  ),
                ),
              FloatingActionButton.extended(
                heroTag: 'setOrigin',
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                onPressed: _setOriginHere,
                icon: const Icon(Icons.my_location_rounded),
                label: Text(getTranslated(context, 'Set origin here')),
              ),
            ],
          ),
        ),
        if (_navigating && !_followEnabled)
          Positioned(
            left: 12,
            bottom: 120,
            child: ElevatedButton.icon(
              onPressed: _onRecenter,
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: const Text('Re-center'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 44), // ← key: NOT infinity
                padding: const EdgeInsets.symmetric(horizontal: 14),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: Colors.black87,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22)),
                elevation: 3,
              ),
            ),
          ),

        // bottom sheet
      ]),
    );
  }
}
