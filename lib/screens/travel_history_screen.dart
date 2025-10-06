// lib/screens/travel_history_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/colors.dart';
import '../localization/language_constants.dart';
import '../utils/geo_utils.dart'; // kept for other helpers if you use it elsewhere
import '../services/travel_history_service.dart';

class TravelHistoryScreen extends StatefulWidget {
  const TravelHistoryScreen({super.key});

  @override
  State<TravelHistoryScreen> createState() => _TravelHistoryScreenState();
}

enum _Sort { recent, oldest, shortestTime, longestDistance }

class _TravelHistoryScreenState extends State<TravelHistoryScreen> {
  final _db = FirebaseDatabase.instance;
  final _auth = FirebaseAuth.instance;

  DatabaseReference? _ref;
  StreamSubscription<DatabaseEvent>? _sub;

  // Data
  List<TravelEntry> _all = [];
  List<TravelEntry> _view = [];
  bool _loading = true;

  // Filters
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String _mode = 'all'; // all | car | metro
  DateTimeRange? _range;
  _Sort _sort = _Sort.recent;

  // Selection mode
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  // ---- Helpers --------------------------------------------------------------

  String tr(String key, String fb) {
    final s = getTranslated(context, key);
    if (s.isEmpty || s.toLowerCase() == 'null') return fb;
    return s;
  }

  bool _isArabic(BuildContext ctx) =>
      Localizations.localeOf(ctx).languageCode.toLowerCase().startsWith('ar');

  String _localizeDigits(BuildContext ctx, String input) {
    if (!_isArabic(ctx)) return input;
    const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    final buf = StringBuffer();
    for (final ch in input.split('')) {
      final i = western.indexOf(ch);
      buf.write(i >= 0 ? arabic[i] : ch);
    }
    return buf.toString();
  }

  /// Localized distance: meters < 1000 show "123 م", otherwise "12.3 كم".
  /// Uses Arabic‑Indic digits when locale is Arabic.
  String _fmtDistance(BuildContext ctx, int meters) {
    final isAr = _isArabic(ctx);
    final mLabel =
        getTranslated(ctx, 'm').isEmpty ? 'm' : getTranslated(ctx, 'm');
    final kmLabel =
        getTranslated(ctx, 'km').isEmpty ? 'km' : getTranslated(ctx, 'km');

    String out;
    if (meters < 1000) {
      out = isAr
          ? '${meters.toString()} $mLabel'
          : '${meters.toString()} $mLabel';
    } else {
      final km = (meters / 1000.0);
      // one decimal like your UI
      final s = km.toStringAsFixed(1);
      // In Arabic we usually show unit after the number as well
      out = '$s $kmLabel';
    }
    return _localizeDigits(ctx, out);
  }

  String _fmtDurationLocalized(BuildContext ctx, int seconds) {
    final m = (seconds / 60).round();
    if (m < 60) {
      final txt = '$m ${tr("min", "min")}';
      return _localizeDigits(ctx, txt);
    }
    final h = m ~/ 60;
    final mm = m % 60;
    final minLabel = tr("min", "min");
    final hrLabel = tr("hr", "hr");
    final txt = '$h $hrLabel ${mm > 0 ? "$mm $minLabel" : ""}'.trim();
    return _localizeDigits(ctx, txt);
  }

  String _fmtClockLocalized(BuildContext ctx, DateTime d) {
    final s = '${_2(d.hour)}:${_2(d.minute)}';
    return _localizeDigits(ctx, s);
  }

  String _shortLocalized(BuildContext ctx, DateTime d) =>
      _localizeDigits(ctx, '${_2(d.month)}/${_2(d.day)}');

  @override
  void initState() {
    super.initState();
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      _ref = _db.ref('App/TravelHistory/$uid');
      _sub = _ref!.onValue.listen((event) {
        final data = event.snapshot.value;
        final list = <TravelEntry>[];
        if (data is Map) {
          data.forEach((id, val) {
            if (val is Map) {
              list.add(TravelEntry.fromMap(
                id as String,
                Map<Object?, Object?>.from(val),
              ));
            }
          });
        }
        setState(() {
          _all = list;
          _applyFilterSort();
          _loading = false;
          // keep selection valid
          _selectedIds.removeWhere((id) => !_all.any((e) => e.id == id));
          if (_selectedIds.isEmpty) _selectionMode = false;
        });
      });
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---- Filtering / sorting --------------------------------------------------

  void _applyFilterSort() {
    Iterable<TravelEntry> it = _all;

    // Mode
    if (_mode != 'all') {
      it = it.where((e) => e.mode == _mode);
    }

    // Query (origin/destination OR station OR line)
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      it = it.where((e) {
        final a = (e.originLabel ?? '').toLowerCase();
        final b = (e.destLabel ?? '').toLowerCase();
        final fs = (e.fromStation ?? '').toLowerCase();
        final ts = (e.toStation ?? '').toLowerCase();
        final lines =
            (e.metroLineKeys ?? const []).map((s) => s.toLowerCase()).join(' ');
        return a.contains(q) ||
            b.contains(q) ||
            fs.contains(q) ||
            ts.contains(q) ||
            lines.contains(q);
      });
    }

    // Date range (inclusive on days)
    if (_range != null) {
      final start =
          DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
      final end = DateTime(_range!.end.year, _range!.end.month, _range!.end.day,
          23, 59, 59, 999);
      it = it.where((e) =>
          e.startedAt
              .isAfter(start.subtract(const Duration(milliseconds: 1))) &&
          e.startedAt.isBefore(end.add(const Duration(milliseconds: 1))));
    }

    // Sort
    final list = it.toList();
    switch (_sort) {
      case _Sort.recent:
        list.sort((a, b) => b.startedAt.compareTo(a.startedAt));
        break;
      case _Sort.oldest:
        list.sort((a, b) => a.startedAt.compareTo(b.startedAt));
        break;
      case _Sort.shortestTime:
        list.sort((a, b) => a.durationSeconds.compareTo(b.durationSeconds));
        break;
      case _Sort.longestDistance:
        list.sort((a, b) => b.distanceMeters.compareTo(a.distanceMeters));
        break;
    }

    setState(() => _view = list);
  }

  void _clearAllFilters() {
    setState(() {
      _query = '';
      _searchCtrl.clear();
      _mode = 'all';
      _range = null;
      _sort = _Sort.recent;
      _applyFilterSort();
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 3);
    final last = DateTime(now.year + 1);
    final init = _range ??
        DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now);
    final res = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: init,
      helpText: tr('filter.dates', 'Dates'),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(
                  primary: const Color(0xFF1B5E20),
                  secondary: const Color(0xFF1B5E20),
                ),
          ),
          child: child!,
        );
      },
    );
    if (res != null) {
      setState(() => _range = res);
      _applyFilterSort();
    }
  }

  // ---- Selection helpers ----------------------------------------------------

  void _enterSelection(TravelEntry e) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(e.id);
    });
  }

  void _toggleSelect(TravelEntry e) {
    setState(() {
      if (_selectedIds.contains(e.id)) {
        _selectedIds.remove(e.id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(e.id);
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _selectAllVisible() {
    setState(() {
      final ids = _view.map((e) => e.id);
      if (_selectedIds.length == _view.length) {
        _selectedIds.clear();
        _selectionMode = false;
      } else {
        _selectedIds
          ..clear()
          ..addAll(ids);
        _selectionMode = true;
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_ref == null || _selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('Delete selected?', 'Delete selected?')),
        content: Text(
          tr('This will permanently remove the selected trips.',
              'This will permanently remove the selected trips.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Delete', 'Delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      final batch = _selectedIds.toList();
      for (final id in batch) {
        await _ref!.child(id).remove();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(tr('Deleted $count trip(s)', 'Deleted $count trip(s)'))),
        );
      }
      _exitSelection();
    }
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.kBackGroundColor,
      appBar: AppBar(
        title: _selectionMode
            ? Text(
                _localizeDigits(context,
                    '${_selectedIds.length} ${tr("Selected", "Selected")}'),
              )
            : Text(tr('Travel history', 'Travel history')),
        centerTitle: true,
        leading: _selectionMode
            ? IconButton(
                tooltip: tr('Close', 'Close'),
                icon: const Icon(Icons.close_rounded),
                onPressed: _exitSelection,
              )
            : null,
        actions: _selectionMode
            ? [
                IconButton(
                  tooltip: tr('Select all', 'Select all'),
                  icon: const Icon(Icons.select_all_rounded),
                  onPressed: _selectAllVisible,
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: tr('Delete selected', 'Delete selected'),
                  icon: const Icon(Icons.delete_forever_rounded),
                  onPressed: _deleteSelected,
                ),
                const SizedBox(width: 6),
              ]
            : [
                PopupMenuButton<_Sort>(
                  tooltip: tr('filter.sort', 'Sort'),
                  onSelected: (v) {
                    setState(() => _sort = v);
                    _applyFilterSort();
                  },
                  itemBuilder: (_) => [
                    _sortItem(
                        _Sort.recent, tr('filter.sort.recent', 'Most recent')),
                    _sortItem(
                        _Sort.oldest, tr('filter.sort.oldest', 'Oldest first')),
                    _sortItem(_Sort.shortestTime,
                        tr('filter.sort.shortest', 'Shortest time')),
                    _sortItem(_Sort.longestDistance,
                        tr('filter.sort.longest', 'Longest distance')),
//                   ],
                  ],
                  icon: const Icon(Icons.sort_rounded),
                ),
                const SizedBox(width: 6),
              ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _view.isEmpty
              ? _emptyState(context)
              : RefreshIndicator(
                  onRefresh: () async => _ref?.keepSynced(true),
                  child: CustomScrollView(
                    slivers: [
                      if (!_selectionMode)
                        SliverToBoxAdapter(child: _searchBar()),
                      if (!_selectionMode)
                        SliverToBoxAdapter(child: _filterRow()),
                      if (!_selectionMode)
                        SliverToBoxAdapter(child: _activeFiltersBar()),
                      ..._buildGroupedList(t),
                      const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    ],
                  ),
                ),
    );
  }

  PopupMenuItem<_Sort> _sortItem(_Sort v, String label) {
    return PopupMenuItem<_Sort>(
      value: v,
      child: Row(
        children: [
          if (_sort == v)
            const Icon(Icons.check_rounded, color: Colors.green)
          else
            const SizedBox(width: 24),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (s) {
          _query = s;
          _applyFilterSort();
        },
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: tr('search.history.hint', 'Search destination or origin'),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.black12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.black12),
          ),
        ),
      ),
    );
  }

  // Overflow-proof filter row (Wrap)
  Widget _filterRow() {
    Widget chip(String key, IconData icon, String label) => ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(label),
            ],
          ),
          selected: _mode == key,
          onSelected: (_) {
            setState(() => _mode = key);
            _applyFilterSort();
          },
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          chip('all', Icons.all_inclusive, tr('All', 'All')),
          chip('car', Icons.directions_car_filled, tr('Car', 'Car')),
          chip('metro', Icons.directions_subway_filled, tr('Metro', 'Metro')),
          OutlinedButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: Text(
              _range == null
                  ? tr('filter.dates', 'Dates')
                  : '${_shortLocalized(context, _range!.start)} – ${_shortLocalized(context, _range!.end)}',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black87,
              side: const BorderSide(color: Colors.black12),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  // Active filters bar (Wrap, never overflows)
  Widget _activeFiltersBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_mode != 'all')
            _pill(
                '${tr("Mode", "Mode")}: ${_mode == "car" ? tr("Car", "Car") : tr("Metro", "Metro")}'),
          if (_query.trim().isNotEmpty)
            _pill('${tr("Search", "Search")}: "${_query.trim()}"'),
          if (_range != null)
            _pill(
                '${_shortLocalized(context, _range!.start)}–${_shortLocalized(context, _range!.end)}'),
          TextButton.icon(
            onPressed: _clearAllFilters,
            icon: const Icon(Icons.filter_alt_off_rounded),
            label: Text(tr('filter.clearAll', 'Clear all')),
          ),
        ],
      ),
    );
  }

  // Group by yyyy-mm-dd
  List<Widget> _buildGroupedList(TextTheme t) {
    final groups = <String, List<TravelEntry>>{};
    for (final e in _view) {
      final k = _dateKey(e.startedAt);
      (groups[k] ??= []).add(e);
    }

    final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return keys.map((k) {
      final items = groups[k]!;
      return SliverList.separated(
        itemCount: items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(_prettyDateHeader(k),
                  style: t.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800, color: Colors.black87)),
            );
          }
          final e = items[i - 1];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _tripCard(e),
          );
        },
      );
    }).toList();
  }

  // Metro line color palette (fallback to teal if unknown)
  Color _lineColor(String key) {
    switch (key.toLowerCase()) {
      case 'blue':
        return const Color(0xFF1976D2);
      case 'red':
        return const Color(0xFFD32F2F);
      case 'green':
        return const Color(0xFF388E3C);
      case 'yellow':
        return const Color(0xFFF9A825);
      case 'orange':
        return const Color(0xFFEF6C00);
      case 'purple':
        return const Color(0xFF7B1FA2);
      default:
        return const Color(0xFF00897B);
    }
  }

  Widget _lineChip(String key) {
    // Show translated color name, e.g., 'Blue' -> 'أزرق'
    final label = getTranslated(
        context, key[0].toUpperCase() + key.substring(1).toLowerCase());
    final shown = (label.isEmpty || label.toLowerCase() == 'null')
        ? (key.isNotEmpty
            ? '${key[0].toUpperCase()}${key.substring(1).toLowerCase()}'
            : key)
        : label;

    final c = _lineColor(key);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(shown, style: TextStyle(fontWeight: FontWeight.w700, color: c)),
        ],
      ),
    );
  }

  Widget _tripCard(TravelEntry e) {
    final isCar = e.mode == 'car';
    final accent = isCar ? const Color(0xFF1976D2) : const Color(0xFF00897B);
    final selected = _selectedIds.contains(e.id);

    // Times (localized)
    final startTime = _fmtClockLocalized(context, e.startedAt);
    final endTime = e.finishedAt != null
        ? _fmtClockLocalized(context, e.finishedAt!)
        : tr('—', '—');

    final lines = e.metroLineKeys ?? const [];

    return InkWell(
      onLongPress: () => _enterSelection(e),
      onTap: () {
        if (_selectionMode) {
          _toggleSelect(e);
        } else {
          _openDetails(e);
        }
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: _selectionMode && selected
              ? Border.all(color: Colors.green.shade600, width: 2)
              : null,
          boxShadow: const [
            BoxShadow(
              blurRadius: 12,
              color: Color(0x14000000),
              offset: Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_selectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => _toggleSelect(e),
                    ),
                  ),
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent, accent.withOpacity(0.65)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isCar
                        ? Icons.directions_car_filled
                        : Icons.directions_subway_filled,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        e.destLabel?.trim().isNotEmpty == true
                            ? e.destLabel!.trim()
                            : tr('Destination', 'Destination'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1B1B1B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Subline
                      Text(
                        '${e.originLabel?.trim().isNotEmpty == true ? e.originLabel!.trim() : tr("From my location", "From my location")} → ${e.destLabel?.trim().isNotEmpty == true ? e.destLabel!.trim() : tr("Destination", "Destination")}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 6),
                      // Chips row
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _chip(
                            icon: Icons.schedule,
                            text: _fmtDurationLocalized(
                                context, e.durationSeconds),
                          ),
                          _chip(
                            icon: Icons.pin_drop_outlined,
                            text: _fmtDistance(context, e.distanceMeters),
                          ),
                          _chip(
                            icon: Icons.play_arrow_rounded,
                            text: '${tr("Start", "Start")}: $startTime',
                          ),
                          _chip(
                            icon: Icons.stop_rounded,
                            text: '${tr("End", "End")}: $endTime',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!_selectionMode)
                  const Icon(Icons.chevron_right_rounded,
                      color: Colors.black38),
              ],
            ),

            // Lines used (metro only)
            if (!isCar && lines.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    tr('Lines used', 'Lines used'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: Colors.black87),
                  ),
                  ...lines.map(_lineChip),
                ],
              ),
              if ((e.fromStation?.isNotEmpty ?? false) ||
                  (e.toStation?.isNotEmpty ?? false)) ...[
                const SizedBox(height: 6),
                Text(
                  '${tr("From", "From")}: ${e.fromStation ?? tr("Unknown", "Unknown")}  •  ${tr("To", "To")}: ${e.toStation ?? tr("Unknown", "Unknown")}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.black87),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF2F6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  // ---- Details bottom sheet -------------------------------------------------

  void _openDetails(TravelEntry e) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true, // <— allow tall content + scrolling
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.9, // <— cap to 90% of screen height
        child: _TripDetailsSheet(
          entry: e,
          onDelete: () async {
            Navigator.of(ctx).pop();
            await _delete(e);
          },
          onNavigateAgain: () {
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(tr(
                    'Opening the main map will let you set this destination again.',
                    'Opening the main map will let you set this destination again.')),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _delete(TravelEntry e) async {
    if (_ref == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('Delete trip?', 'Delete trip?')),
        content: Text(tr(
            'This will permanently remove this trip from your history.',
            'This will permanently remove this trip from your history.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Cancel', 'Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Delete', 'Delete'))),
        ],
      ),
    );
    if (ok == true) {
      await _ref!.child(e.id).remove();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Trip deleted', 'Trip deleted'))),
        );
      }
    }
  }

  // ---- Misc helpers ---------------------------------------------------------

  String _dateKey(DateTime dt) => '${dt.year}-${_2(dt.month)}-${_2(dt.day)}';

  String _prettyDateHeader(String key) {
    final parts = key.split('-').map((e) => int.tryParse(e) ?? 1).toList();
    final dt = DateTime(parts[0], parts[1], parts[2]);
    final now = DateTime.now();
    final d = DateTime(dt.year, dt.month, dt.day);
    final today = DateTime(now.year, now.month, now.day);
    final yday = today.subtract(const Duration(days: 1));
    if (d == today) return tr('Today', 'Today');
    if (d == yday) return tr('Yesterday', 'Yesterday');
    return '${dt.year}-${_2(dt.month)}-${_2(dt.day)}';
  }

  String _2(int n) => n.toString().padLeft(2, '0');

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.route_rounded, size: 64, color: Colors.black26),
            const SizedBox(height: 12),
            Text(
              tr('No trips yet', 'No trips yet'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              tr('Your trips will appear here', 'Your trips will appear here'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

// === Details sheet (no map) ==================================================

class _TripDetailsSheet extends StatefulWidget {
  final TravelEntry entry;
  final VoidCallback onDelete;
  final VoidCallback onNavigateAgain;

  const _TripDetailsSheet({
    required this.entry,
    required this.onDelete,
    required this.onNavigateAgain,
  });

  @override
  State<_TripDetailsSheet> createState() => _TripDetailsSheetState();
}

class _TripDetailsSheetState extends State<_TripDetailsSheet> {
  bool _isArabic(BuildContext ctx) =>
      Localizations.localeOf(ctx).languageCode.toLowerCase().startsWith('ar');

  String _localizeDigits(BuildContext ctx, String input) {
    if (!_isArabic(ctx)) return input;
    const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    final buf = StringBuffer();
    for (final ch in input.split('')) {
      final i = western.indexOf(ch);
      buf.write(i >= 0 ? arabic[i] : ch);
    }
    return buf.toString();
  }

  String _fmtDistance(BuildContext ctx, int meters) {
    final mLabel =
        getTranslated(ctx, 'm').isEmpty ? 'm' : getTranslated(ctx, 'm');
    final kmLabel =
        getTranslated(ctx, 'km').isEmpty ? 'km' : getTranslated(ctx, 'km');
    String out;
    if (meters < 1000) {
      out = '$meters $mLabel';
    } else {
      final s = (meters / 1000.0).toStringAsFixed(1);
      out = '$s $kmLabel';
    }
    return _localizeDigits(ctx, out);
  }

  String _fmtClock(BuildContext ctx, DateTime dt) =>
      _localizeDigits(ctx, '${_2(dt.hour)}:${_2(dt.minute)}');

  String _fmtDuration(BuildContext ctx, int seconds) {
    final m = (seconds / 60).round();
    if (m < 60) return _localizeDigits(ctx, '$m ${getTranslated(ctx, "min")}');
    final h = m ~/ 60;
    final mm = m % 60;
    final txt =
        '$h ${getTranslated(ctx, "hr")} ${mm > 0 ? "$mm ${getTranslated(ctx, "min")}" : ""}';
    return _localizeDigits(ctx, txt.trim());
  }

  String _friendlyDate(BuildContext ctx, DateTime dt) {
    final now = DateTime.now();
    final d = DateTime(dt.year, dt.month, dt.day);
    final today = DateTime(now.year, now.month, now.day);
    final yday = today.subtract(const Duration(days: 1));
    if (d == today) return getTranslated(ctx, 'Today');
    if (d == yday) return getTranslated(ctx, 'Yesterday');
    final raw =
        '${dt.year}-${_2(dt.month)}-${_2(dt.day)} ${_2(dt.hour)}:${_2(dt.minute)}';
    return _localizeDigits(ctx, raw);
  }

  Color _lineColor(String key) {
    switch (key.toLowerCase()) {
      case 'blue':
        return const Color(0xFF1976D2);
      case 'red':
        return const Color(0xFFD32F2F);
      case 'green':
        return const Color(0xFF388E3C);
      case 'yellow':
        return const Color(0xFFF9A825);
      case 'orange':
        return const Color(0xFFEF6C00);
      case 'purple':
        return const Color(0xFF7B1FA2);
      default:
        return const Color(0xFF00897B);
    }
  }

  Widget _lineChip(String key) {
    final translated = getTranslated(
        context, key[0].toUpperCase() + key.substring(1).toLowerCase());
    final text = (translated.isEmpty || translated.toLowerCase() == 'null')
        ? (key.isNotEmpty
            ? '${key[0].toUpperCase()}${key.substring(1).toLowerCase()}'
            : key)
        : translated;

    final c = _lineColor(key);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: c)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final lines = e.metroLineKeys ?? const [];

    // --- SCROLLABLE CONTENT to avoid overflow ---
    return SafeArea(
      child: LayoutBuilder(
        builder: (ctx, cons) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ConstrainedBox(
            constraints:
                BoxConstraints(minHeight: 0, maxHeight: cons.maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Summary chips (Wrap to avoid overflow)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _modeBadge(context, e.mode),
                      _chip(Icons.schedule,
                          _fmtDuration(context, e.durationSeconds)),
                      _chip(Icons.pin_drop_outlined,
                          _fmtDistance(context, e.distanceMeters)),
                      _datePill(_friendlyDate(context, e.startedAt)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Lines used (metro only)
                if (e.mode == 'metro' && lines.isNotEmpty) ...[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        Text(getTranslated(context, 'Lines used'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                        ...lines.map(_lineChip),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Origin / Destination, stations
                _kv(getTranslated(context, 'Origin'),
                    e.originLabel ?? getTranslated(context, 'Unknown')),
                _kv(getTranslated(context, 'Destination'),
                    e.destLabel ?? getTranslated(context, 'Unknown')),
                if (e.mode == 'metro') ...[
                  _kv(getTranslated(context, 'From station'),
                      e.fromStation ?? getTranslated(context, 'Unknown')),
                  _kv(getTranslated(context, 'To station'),
                      e.toStation ?? getTranslated(context, 'Unknown')),
                ],

                // Start / End times
                _kv(getTranslated(context, 'Start time'),
                    _fmtClock(context, e.startedAt)),
                _kv(
                    getTranslated(context, 'End time'),
                    e.finishedAt == null
                        ? getTranslated(context, '—')
                        : _fmtClock(context, e.finishedAt!)),

                const SizedBox(height: 14),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.onNavigateAgain,
                        icon: const Icon(Icons.navigation_rounded),
                        label: Text(getTranslated(context, 'Navigate again')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600),
                        onPressed: widget.onDelete,
                        icon: const Icon(Icons.delete_forever_rounded,
                            color: Colors.white),
                        label: Text(getTranslated(context, 'Delete'),
                            style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- UI helpers (unchanged except numbers localization) ---
  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
                child: Text(k,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13))),
            Expanded(
              flex: 2,
              child: Text(v,
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: Colors.black87),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );

  Widget _chip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7F9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: Colors.black87),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _datePill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF3F6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event, size: 16, color: Colors.black87),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _modeBadge(BuildContext ctx, String mode) {
    final icon = mode == 'car'
        ? Icons.directions_car_filled
        : Icons.directions_subway_filled;
    final label = getTranslated(ctx, mode == 'car' ? 'Car' : 'Metro');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(18)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }

  String _2(int n) => n.toString().padLeft(2, '0');
}

// ===== Data model (ADDED metro fields) =======================================

class TravelEntry {
  final String id;
  final String mode; // 'car' | 'metro'
  final String? originLabel;
  final String? destLabel;
  final LatLng? originLL;
  final LatLng? destLL;
  final int durationSeconds;
  final int distanceMeters;
  final DateTime startedAt;
  final DateTime? finishedAt; // may be null

  // NEW: metro-specific metadata
  final List<String>? metroLineKeys; // e.g. ["Blue","Purple"]
  final String? fromStation; // optional
  final String? toStation; // optional

  TravelEntry({
    required this.id,
    required this.mode,
    required this.originLabel,
    required this.destLabel,
    required this.originLL,
    required this.destLL,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.startedAt,
    required this.finishedAt,
    this.metroLineKeys,
    this.fromStation,
    this.toStation,
  });

  Map<String, dynamic> toMap() => {
        'mode': mode,
        'originLabel': originLabel,
        'destLabel': destLabel,
        'originLat': originLL?.latitude,
        'originLng': originLL?.longitude,
        'destLat': destLL?.latitude,
        'destLng': destLL?.longitude,
        'durationSeconds': durationSeconds,
        'distanceMeters': distanceMeters,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'finishedAt': finishedAt?.millisecondsSinceEpoch,
        // NEW
        'metroLineKeys': metroLineKeys,
        'fromStation': fromStation,
        'toStation': toStation,
      };

  static List<String>? _readLines(dynamic v) {
    if (v == null) return null;
    if (v is List) {
      // ensure strings & Capitalize first letter (key used for color/translation)
      return v
          .map((e) => (e?.toString() ?? '').trim())
          .where((s) => s.isNotEmpty)
          .map((s) => s[0].toUpperCase() + s.substring(1).toLowerCase())
          .toList();
    }
    return null;
  }

  factory TravelEntry.fromMap(String id, Map<Object?, Object?> m) {
    LatLng? _ll(String a, String b) {
      final lat = (m[a] as num?)?.toDouble();
      final lng = (m[b] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return LatLng(lat, lng);
    }

    return TravelEntry(
      id: id,
      mode: (m['mode'] ?? 'car') as String,
      originLabel: (m['originLabel'] ?? '') as String?,
      destLabel: (m['destLabel'] ?? '') as String?,
      originLL: _ll('originLat', 'originLng'),
      destLL: _ll('destLat', 'destLng'),
      durationSeconds: (m['durationSeconds'] as num?)?.toInt() ?? 0,
      distanceMeters: (m['distanceMeters'] as num?)?.toInt() ?? 0,
      startedAt: DateTime.fromMillisecondsSinceEpoch(
          (m['startedAt'] as num?)?.toInt() ?? 0),
      finishedAt: (m['finishedAt'] == null)
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (m['finishedAt'] as num).toInt()),
      // NEW
      metroLineKeys: _readLines(m['metroLineKeys']),
      fromStation: (m['fromStation'] ?? m['from_station'] ?? '') as String?,
      toStation: (m['toStation'] ?? m['to_station'] ?? '') as String?,
    );
  }
}
