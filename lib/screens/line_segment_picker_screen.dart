import 'package:flutter/material.dart';
import '../widgets/all_metro_lines.dart'; // provides metroLineColors

// ─────────────────────────────────────────────────────────────────────────────
// Result model returned to caller
// ─────────────────────────────────────────────────────────────────────────────
class LineSegmentResult {
  final int fromIndex;
  final int toIndex;
  final bool startToEnd;

  /// Readable, localized label like:
  /// "Red line: King Saud University → King Fahd Sport City"
  final String displayLabel;

  LineSegmentResult({
    required this.fromIndex,
    required this.toIndex,
    required this.startToEnd,
    required this.displayLabel,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Localized line label from a lineKey like 'red','blue',...
String lineLabel(BuildContext context, String lineKey) {
  final isAr = Directionality.of(context) == TextDirection.rtl;
  const en = {
    'red': 'Red line',
    'blue': 'Blue line',
    'green': 'Green line',
    'orange': 'Orange line',
    'purple': 'Purple line',
    'yellow': 'Yellow line',
  };
  const ar = {
    'red': 'الخط الأحمر',
    'blue': 'الخط الأزرق',
    'green': 'الخط الأخضر',
    'orange': 'الخط البرتقالي',
    'purple': 'الخط الأرجواني',
    'yellow': 'الخط الأصفر',
  };
  final map = isAr ? ar : en;
  return map[lineKey.toLowerCase()] ?? lineKey; // never null
}

/// Pick the proper visible station name from a station map {name, nameAr, ...}
String stationLabel(BuildContext context, Map<String, dynamic> s) {
  final isAr = Directionality.of(context) == TextDirection.rtl;
  final dynamic raw = isAr ? (s['nameAr'] ?? s['name']) : s['name'];
  return (raw ?? '') as String;
}

/// Capitalize first letter (for safety with titles if needed)
String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class LineSegmentPickerScreen extends StatefulWidget {
  final String lineKey; // e.g. 'green'
  /// Each station: { 'name': String, 'nameAr': String?, 'lat': double, 'lng': double }
  final List<Map<String, dynamic>> stations;
  final bool startToEnd;

  const LineSegmentPickerScreen({
    super.key,
    required this.lineKey,
    required this.stations,
    this.startToEnd = true,
  });

  @override
  State<LineSegmentPickerScreen> createState() =>
      _LineSegmentPickerScreenState();
}

class _LineSegmentPickerScreenState extends State<LineSegmentPickerScreen> {
  late bool _startToEnd;
  late int _fromIndex;
  late int _toIndex;

  @override
  void initState() {
    super.initState();
    _startToEnd = widget.startToEnd;
    _fromIndex = 0;
    _toIndex = (widget.stations.length - 1).clamp(0, 9999);
  }

  List<Map<String, dynamic>> get _ordered =>
      _startToEnd ? widget.stations : widget.stations.reversed.toList();

  // translate index from ordered list back to real (0..N-1)
  int _toRealIndex(int idxInOrdered) {
    if (_startToEnd) return idxInOrdered;
    return widget.stations.length - 1 - idxInOrdered;
  }

  @override
  Widget build(BuildContext context) {
    final color = metroLineColors[widget.lineKey] ?? Colors.black87;
    final isRTL = Directionality.of(context) == TextDirection.rtl;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.6,
        title: Text(
          isRTL
              ? 'اختر مقطع — ${lineLabel(context, widget.lineKey)}'
              : 'Choose segment — ${lineLabel(context, widget.lineKey)}',
          style: const TextStyle(
              fontWeight: FontWeight.w700, color: Colors.black87),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      backgroundColor: const Color(0xFFF6F9F3),
      body: SafeArea(
        child: Column(
          children: [
            // Direction toggle
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  _DirChip(
                    label: isRTL ? 'البداية→النهاية' : 'Start→End',
                    selected: _startToEnd,
                    onTap: () {
                      setState(() {
                        _startToEnd = true;
                        _fromIndex = 0;
                        _toIndex = widget.stations.length - 1;
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  _DirChip(
                    label: isRTL ? 'النهاية→البداية' : 'End→Start',
                    selected: !_startToEnd,
                    onTap: () {
                      setState(() {
                        _startToEnd = false;
                        _fromIndex = 0;
                        _toIndex = widget.stations.length - 1;
                      });
                    },
                  ),
                ],
              ),
            ),

            // From / To pickers
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Column(
                children: [
                  _StationPicker(
                    label: isRTL ? 'من' : 'From',
                    color: color,
                    valueIndex: _fromIndex,
                    items: _ordered
                        .map<String>((s) => stationLabel(context, s))
                        .toList(),
                    onChanged: (i) {
                      // ensure from < to in ordered list
                      if (i >= _toIndex) {
                        setState(() {
                          _fromIndex = i;
                          _toIndex = (i + 1).clamp(0, _ordered.length - 1);
                        });
                      } else {
                        setState(() => _fromIndex = i);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  _StationPicker(
                    label: isRTL ? 'إلى' : 'To',
                    color: color,
                    valueIndex: _toIndex,
                    items: _ordered
                        .map<String>((s) => stationLabel(context, s))
                        .toList(),
                    onChanged: (i) {
                      if (i <= _fromIndex) {
                        setState(() {
                          _toIndex = i;
                          _fromIndex = (i - 1).clamp(0, _ordered.length - 2);
                        });
                      } else {
                        setState(() => _toIndex = i);
                      }
                    },
                  ),
                ],
              ),
            ),

            // Stations list with range indication
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 6,
                      color: Colors.black12,
                      offset: Offset(0, 2),
                    )
                  ],
                ),
                child: ListView.separated(
                  itemCount: _ordered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final title = stationLabel(context, _ordered[i]);
                    final inRange = i >= _fromIndex && i <= _toIndex;
                    return ListTile(
                      dense: true,
                      leading: _Dot(inRange: inRange, color: color),
                      title: Text(
                        title,
                        style: TextStyle(
                          fontWeight:
                              inRange ? FontWeight.w700 : FontWeight.w500,
                          color: inRange ? Colors.black : Colors.black87,
                        ),
                      ),
                      onTap: () {
                        // tapping a station smartly adjusts nearest end
                        final dStart = (i - _fromIndex).abs();
                        final dEnd = (i - _toIndex).abs();
                        setState(() {
                          if (dStart <= dEnd) {
                            _fromIndex = i.clamp(0, _toIndex);
                          } else {
                            _toIndex = i.clamp(_fromIndex, _ordered.length - 1);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ),

            // Show segment button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.route),
                  label: Text(
                    isRTL ? 'عرض المقطع' : 'Show segment',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                  ),
                  onPressed: () {
                    final realFrom = _toRealIndex(_fromIndex);
                    final realTo = _toRealIndex(_toIndex);

                    final fromName =
                        stationLabel(context, widget.stations[realFrom]);
                    final toName =
                        stationLabel(context, widget.stations[realTo]);
                    final label =
                        '${lineLabel(context, widget.lineKey)}: $fromName \u2192 $toName';

                    Navigator.of(context).pop(LineSegmentResult(
                      fromIndex: realFrom,
                      toIndex: realTo,
                      startToEnd: _startToEnd,
                      displayLabel: label, // caller can show without nulls
                    ));
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UI bits
// ─────────────────────────────────────────────────────────────────────────────

class _DirChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DirChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _StationPicker extends StatelessWidget {
  final String label;
  final Color color;
  final int valueIndex;
  final List<String> items;
  final ValueChanged<int> onChanged;

  const _StationPicker({
    required this.label,
    required this.color,
    required this.valueIndex,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black12),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: valueIndex,
          items: [
            for (int i = 0; i < items.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text(
                  items[i],
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool inRange;
  final Color color;
  const _Dot({required this.inRange, required this.color});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 11,
      backgroundColor: inRange ? color : Colors.white,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: inRange ? color.withOpacity(0.0) : Colors.black26,
            width: 2,
          ),
        ),
      ),
    );
  }
}
