import 'dart:math' as math;
import 'package:flutter/material.dart';

class MetroStop {
  final String id;
  final String nameEn;
  final String nameAr;
  final bool isTransfer;
  final List<String> transferLines;

  const MetroStop({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    this.isTransfer = false,
    this.transferLines = const [],
  });
}

/// Launches the onboard (bottom‑sheet) display.
Future<void> showOnboardDisplay(
  BuildContext context, {
  // REQUIRED (same as before)
  required List<MetroStop> stops,
  required int currentIndex,
  required String lineKey,
  required Color lineColor,
  String? directionNameEn,
  String? directionNameAr,
  Duration? etaToNext,
  bool isRTL = false,
  bool forward = true,

  // Keeps sheet in sync with banner
  String? nextStationOverride,

  // Optional “full line / next line” support (unchanged)
  List<MetroStop>? fullLineStops,
  bool autoBuildSegmentFromFull = true,
  List<MetroStop>? nextLinePreviewStops,
  String? nextLineKey,
  Color? nextLineColor,
  String? nextDirectionNameEn,
  String? nextDirectionNameAr,

  // Existing next‑stop action signals
  bool alightHere = false, // show “Alight here”
  bool transferHere = false, // show “Transfer here”
  String? transferToLineKey, // e.g. "red"

  // NEW — prepare-to-transfer (heads-up soon)
  bool prepareTransferSoon = false, // show “Get ready …”
  int prepareTransferStopsAway = 0, // e.g., 2
  String? prepareTransferToLineKey, // e.g., "red"
  String? prepareAtStationName, // e.g., "King Abdullah FD"
}) async {
  assert(stops.isNotEmpty);
  currentIndex = currentIndex.clamp(0, stops.length - 1);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return Directionality(
        textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
        child: _OnboardPanel(
          // base (current line)
          stops: stops,
          currentIndex: currentIndex,
          lineKey: lineKey,
          lineColor: lineColor,
          directionNameEn: directionNameEn,
          directionNameAr: directionNameAr,
          etaToNext: etaToNext,
          isRTL: isRTL,
          forward: forward,
          nextStationOverride: nextStationOverride,

          // toggles (optional)
          fullLineStops: fullLineStops,
          autoBuildSegmentFromFull: autoBuildSegmentFromFull,

          // next line preview (optional)
          nextLinePreviewStops: nextLinePreviewStops,
          nextLineKey: nextLineKey,
          nextLineColor: nextLineColor,
          nextDirectionNameEn: nextDirectionNameEn,
          nextDirectionNameAr: nextDirectionNameAr,

          // Existing action flags
          alightHere: alightHere,
          transferHere: transferHere,
          transferToLineKey: transferToLineKey,

          // NEW prepare flags
          prepareTransferSoon: prepareTransferSoon,
          prepareTransferStopsAway: prepareTransferStopsAway,
          prepareTransferToLineKey: prepareTransferToLineKey,
          prepareAtStationName: prepareAtStationName,
        ),
      );
    },
  );
}

enum _ViewMode { segment, fullLine, nextLine }

class _OnboardPanel extends StatefulWidget {
  const _OnboardPanel({
    required this.stops,
    required this.currentIndex,
    required this.lineKey,
    required this.lineColor,
    required this.isRTL,
    required this.forward,
    this.directionNameEn,
    this.directionNameAr,
    this.etaToNext,
    this.nextStationOverride,
    this.fullLineStops,
    this.autoBuildSegmentFromFull = true,
    this.nextLinePreviewStops,
    this.nextLineKey,
    this.nextLineColor,
    this.nextDirectionNameEn,
    this.nextDirectionNameAr,

    // Existing action flags
    this.alightHere = false,
    this.transferHere = false,
    this.transferToLineKey,

    // NEW prepare flags
    this.prepareTransferSoon = false,
    this.prepareTransferStopsAway = 0,
    this.prepareTransferToLineKey,
    this.prepareAtStationName,
  });

  final List<MetroStop> stops;
  final int currentIndex;
  final String lineKey;
  final Color lineColor;
  final String? directionNameEn;
  final String? directionNameAr;
  final Duration? etaToNext;
  final bool isRTL;
  final bool forward;
  final String? nextStationOverride;

  final List<MetroStop>? fullLineStops;
  final bool autoBuildSegmentFromFull;

  final List<MetroStop>? nextLinePreviewStops;
  final String? nextLineKey;
  final Color? nextLineColor;
  final String? nextDirectionNameEn;
  final String? nextDirectionNameAr;

  // Existing action flags
  final bool alightHere;
  final bool transferHere;
  final String? transferToLineKey;

  // NEW prepare flags
  final bool prepareTransferSoon;
  final int prepareTransferStopsAway;
  final String? prepareTransferToLineKey;
  final String? prepareAtStationName;

  @override
  State<_OnboardPanel> createState() => _OnboardPanelState();
}

class _OnboardPanelState extends State<_OnboardPanel>
    with SingleTickerProviderStateMixin {
  // animation
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))
        ..repeat();
  late final Animation<double> _curve =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);

  final _scrollCtrl = ScrollController();
  late _ViewMode _mode;

  // ───────────── Localization helpers ─────────────
  bool get _rtl => widget.isRTL;

  String _t(String en, String ar) => _rtl ? ar : en;

  String _localizeDigits(String input) {
    if (!_rtl) return input;
    const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    final buf = StringBuffer();
    for (final ch in input.split('')) {
      final i = western.indexOf(ch);
      buf.write(i >= 0 ? arabic[i] : ch);
    }
    return buf.toString();
  }

  // Localized color/line names for display
  String _lineNameLocalized(String key) {
    switch (key.toLowerCase()) {
      case 'blue':
        return _t('Blue', 'الأزرق');
      case 'red':
        return _t('Red', 'الأحمر');
      case 'green':
        return _t('Green', 'الأخضر');
      case 'yellow':
        return _t('Yellow', 'الأصفر');
      case 'orange':
        return _t('Orange', 'البرتقالي');
      case 'purple':
        return _t('Purple', 'الأرجواني');
      default:
        // Capitalize unknown keys
        final s = key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);
        return s;
    }
  }

  String _fmtEta(Duration d) {
    if (d.inMinutes >= 1) {
      final txt = '${d.inMinutes} ${_t("min", "دقيقة")}';
      return _localizeDigits(txt);
    }
    final txt = '${d.inSeconds}${_t("s", " ث")}'.trim();
    return _localizeDigits(txt);
  }

  String _ld(String s) => _localizeDigits(s);

  @override
  void initState() {
    super.initState();
    _mode = _initialMode();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerCurrent());
  }

  _ViewMode _initialMode() {
    if (widget.fullLineStops != null && widget.autoBuildSegmentFromFull) {
      return _ViewMode.segment;
    }
    return _ViewMode.segment;
  }

  void _centerCurrent() {
    const itemExtent = 120.0;
    final idx = _derivedCurrentIndex().toDouble();
    final target = (idx * itemExtent) -
        (MediaQuery.of(context).size.width / 2) +
        (itemExtent / 2);
    final max = _scrollCtrl.position.hasPixels
        ? _scrollCtrl.position.maxScrollExtent
        : 0.0;
    _scrollCtrl.jumpTo(target.clamp(0.0, max));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ---------------- data per mode ----------------
  List<MetroStop> _activeStops() {
    switch (_mode) {
      case _ViewMode.segment:
        if (widget.fullLineStops != null &&
            widget.fullLineStops!.isNotEmpty &&
            widget.autoBuildSegmentFromFull) {
          return _segmentFromFull(
            widget.fullLineStops!,
            _fullIndexFromIdOrName(widget.stops[widget.currentIndex]),
            forward: widget.forward,
          );
        }
        return widget.stops;
      case _ViewMode.fullLine:
        return (widget.fullLineStops != null &&
                widget.fullLineStops!.isNotEmpty)
            ? widget.fullLineStops!
            : widget.stops;
      case _ViewMode.nextLine:
        return widget.nextLinePreviewStops ?? const <MetroStop>[];
    }
  }

  String _activeLineKey() => _mode == _ViewMode.nextLine
      ? (widget.nextLineKey ?? widget.lineKey)
      : widget.lineKey;

  Color _activeLineColor() => _mode == _ViewMode.nextLine
      ? (widget.nextLineColor ?? widget.lineColor)
      : widget.lineColor;

  String _activeDirEn(List<MetroStop> stops) {
    if (_mode == _ViewMode.nextLine) {
      return widget.nextDirectionNameEn ??
          (stops.isNotEmpty ? 'To ${stops.last.nameEn}' : '');
    }
    return widget.directionNameEn ??
        (widget.forward
            ? 'To ${stops.last.nameEn}'
            : 'To ${stops.first.nameEn}');
  }

  String _activeDirAr(List<MetroStop> stops) {
    if (_mode == _ViewMode.nextLine) {
      return widget.nextDirectionNameAr ??
          (stops.isNotEmpty ? 'إلى ${stops.last.nameAr}' : '');
    }
    return widget.directionNameAr ??
        (widget.forward
            ? 'إلى ${stops.last.nameAr}'
            : 'إلى ${stops.first.nameAr}');
  }

  bool get _hasFullLine =>
      (widget.fullLineStops != null && widget.fullLineStops!.length >= 2);
  bool get _hasNextLine => (widget.nextLinePreviewStops != null &&
      widget.nextLinePreviewStops!.isNotEmpty);

  // ------------- helpers -------------
  int _fullIndexFromIdOrName(MetroStop s) {
    final list = widget.fullLineStops ?? widget.stops;
    final byId = list.indexWhere((x) => x.id == s.id);
    if (byId != -1) return byId;
    final byName = list.indexWhere((x) =>
        x.nameEn.toLowerCase() == s.nameEn.toLowerCase() ||
        x.nameAr.toLowerCase() == s.nameAr.toLowerCase());
    return (byName != -1) ? byName : 0;
  }

  List<MetroStop> _segmentFromFull(
    List<MetroStop> full,
    int startIdx, {
    required bool forward,
  }) {
    int a = startIdx;
    int b = startIdx;

    bool atTerminal(int i) => i <= 0 || i >= full.length - 1;

    int i = startIdx;
    while (true) {
      final last = (i >= full.length - 1);
      if (last) break;
      final nextIsTransfer =
          full[i + 1].isTransfer || full[i + 1].transferLines.isNotEmpty;
      b = i + 1;
      if (nextIsTransfer || atTerminal(b)) break;
      i++;
    }

    a = (a - 1).clamp(0, b);
    return full.sublist(a, b + 1);
  }

  /// Uses nextStationOverride (if any) to **derive** the effective current index,
  /// so the timeline highlight matches the green banner’s “Next station”.
  int _derivedCurrentIndex() {
    final stops = _activeStops();

    // Start from default current index per mode
    int baseCurrent;
    switch (_mode) {
      case _ViewMode.segment:
        if (widget.fullLineStops != null &&
            widget.fullLineStops!.isNotEmpty &&
            widget.autoBuildSegmentFromFull) {
          baseCurrent = 0; // rider anchored at 0 in the sliced segment
        } else {
          baseCurrent = widget.currentIndex.clamp(0, stops.length - 1);
        }
        break;
      case _ViewMode.fullLine:
        if (widget.fullLineStops != null && widget.fullLineStops!.isNotEmpty) {
          baseCurrent =
              _fullIndexFromIdOrName(widget.stops[widget.currentIndex])
                  .clamp(0, stops.length - 1);
        } else {
          baseCurrent = widget.currentIndex.clamp(0, stops.length - 1);
        }
        break;
      case _ViewMode.nextLine:
        baseCurrent = 0;
        break;
    }

    // If there’s an explicit next station from the banner, derive current from it.
    if (widget.nextStationOverride != null &&
        widget.nextStationOverride!.trim().isNotEmpty &&
        stops.isNotEmpty) {
      final want = widget.nextStationOverride!.trim().toLowerCase();
      final nextIdx = stops.indexWhere((s) =>
          s.nameEn.toLowerCase() == want || s.nameAr.toLowerCase() == want);
      if (nextIdx != -1) {
        final derived = widget.forward ? (nextIdx - 1) : (nextIdx + 1);
        return derived.clamp(0, stops.length - 1);
      }
    }

    return baseCurrent;
  }

  int _derivedNextIndex(int currentIdx, int total) {
    return widget.forward
        ? (currentIdx + 1).clamp(0, total - 1)
        : (currentIdx - 1).clamp(0, total - 1);
  }

  // -------- build --------
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final isDark = t.brightness == Brightness.dark;

    final activeStops = _activeStops();
    final currentIdx = _derivedCurrentIndex();
    final nextIdx = _derivedNextIndex(currentIdx, activeStops.length);

    final lineKey = _activeLineKey();
    final lineColor = _activeLineColor();
    final dirTextEn = _activeDirEn(activeStops);
    final dirTextAr = _activeDirAr(activeStops);

    final nextStop = activeStops.isNotEmpty
        ? activeStops[nextIdx]
        : const MetroStop(id: 'n/a', nameEn: '-', nameAr: '-');

    final hasTransfers = activeStops.any((s) => s.transferLines.isNotEmpty);
    final double timelineH = hasTransfers ? 150.0 : 120.0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 12),

            // Header
            Row(
              children: [
                Container(
                  width: 12,
                  height: 36,
                  decoration: BoxDecoration(
                    color: lineColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // “Line Blue” -> “الخط الأزرق”
                      Text(
                        '${_t("Line", "الخط")} ${_lineNameLocalized(lineKey)}',
                        style: t.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _rtl ? dirTextAr : dirTextEn,
                        style: t.textTheme.bodyMedium
                            ?.copyWith(color: t.hintColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (widget.etaToNext != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule, size: 18),
                      const SizedBox(width: 6),
                      Text(_fmtEta(widget.etaToNext!),
                          style: t.textTheme.bodyMedium),
                    ],
                  ),
              ],
            ),

            // Action banner (alight / transfer / prepare)
            if (widget.alightHere ||
                widget.transferHere ||
                widget.prepareTransferSoon) ...[
              const SizedBox(height: 10),
              _NextActionBanner(
                alight: widget.alightHere,
                transfer: widget.transferHere,
                transferToLineKey: widget.transferToLineKey,
                // NEW prepare
                prepare: widget.prepareTransferSoon,
                prepareStopsAway: widget.prepareTransferStopsAway,
                prepareToLineKey: widget.prepareTransferToLineKey,
                prepareAtStation: widget.prepareAtStationName,
                rtl: _rtl,
                localizeDigits: _localizeDigits,
                lineNameLocalized: _lineNameLocalized,
                tr: _t,
              ),
            ],

            if (_hasFullLine || _hasNextLine) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  if (_hasFullLine)
                    ChoiceChip(
                      selected: _mode == _ViewMode.segment,
                      label: Text(_t('Segment', 'مقطع')),
                      onSelected: (_) => setState(() {
                        _mode = _ViewMode.segment;
                        _centerCurrent();
                      }),
                    ),
                  if (_hasFullLine)
                    ChoiceChip(
                      selected: _mode == _ViewMode.fullLine,
                      label: Text(_t('Full line', 'الخط الكامل')),
                      onSelected: (_) => setState(() {
                        _mode = _ViewMode.fullLine;
                        _centerCurrent();
                      }),
                    ),
                  if (_hasNextLine)
                    ChoiceChip(
                      selected: _mode == _ViewMode.nextLine,
                      label: Text(_t('Next line', 'الخط التالي')),
                      onSelected: (_) => setState(() {
                        _mode = _ViewMode.nextLine;
                        _centerCurrent();
                      }),
                    ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            // Timeline
            SizedBox(
              height: timelineH,
              child: AnimatedBuilder(
                animation: _curve,
                builder: (context, _) {
                  final animT = _curve.value; // 0..1 curved
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter:
                                _BaselinePainter(lineColor.withOpacity(0.35)),
                          ),
                        ),
                      ),
                      ListView.builder(
                        controller: _scrollCtrl,
                        scrollDirection: Axis.horizontal,
                        itemExtent: 120,
                        itemCount: activeStops.length,
                        itemBuilder: (context, i) {
                          final stop = activeStops[i];
                          final isCurrent = i == currentIdx;
                          final isPassed =
                              widget.forward ? i < currentIdx : i > currentIdx;
                          final isNext = i == nextIdx;

                          return _StationColumn(
                            stop: stop,
                            lineColor: lineColor,
                            state: isCurrent
                                ? StationState.current
                                : (isPassed
                                    ? StationState.passed
                                    : StationState.upcoming),
                            // show moving elements on current & next
                            showTrainHere: isCurrent,
                            trainT: animT,
                            animPhase: animT,
                            isNextDot: isNext,
                            rtl: widget.isRTL,
                            forward: widget.forward,
                            lineNameLocalized:
                                _lineNameLocalized, // ✅ pass the callback here
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 6),

            // Next station card + chips
            _NextCard(
              title: _t('Next station', 'المحطة التالية'),
              name: _rtl ? nextStop.nameAr : nextStop.nameEn,
              transfers: nextStop.transferLines,
              accent: lineColor,

              // chips
              alightHere: widget.alightHere,
              transferHere: widget.transferHere,
              transferToLineKey: widget.transferToLineKey,
              rtl: widget.isRTL,

              // NEW prepare chip data
              prepareTransferSoon: widget.prepareTransferSoon,
              prepareTransferStopsAway: widget.prepareTransferStopsAway,
              prepareTransferToLineKey: widget.prepareTransferToLineKey,
              prepareAtStationName: widget.prepareAtStationName,

              // localization utils
              localizeDigits: _localizeDigits,
              lineNameLocalized: _lineNameLocalized,
              tr: _t,
            ),
          ],
        ),
      ),
    );
  }
}

enum StationState { passed, current, upcoming }

class _StationColumn extends StatelessWidget {
  const _StationColumn({
    required this.stop,
    required this.lineColor,
    required this.state,
    required this.showTrainHere,
    required this.trainT,
    required this.animPhase,
    required this.isNextDot,
    required this.rtl,
    required this.forward,
    required this.lineNameLocalized, // <-- added
  });

  final MetroStop stop;
  final Color lineColor;
  final StationState state;
  final bool showTrainHere;
  final double trainT; // 0..1 travel between current & next
  final double animPhase; // 0..1 loop for pulse/chevrons
  final bool isNextDot;

  final bool rtl;
  final bool forward;

  // Localizer passed from parent (_OnboardPanelState._lineNameLocalized)
  final String Function(String) lineNameLocalized;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final name = rtl ? stop.nameAr : stop.nameEn;

    final dotColor = switch (state) {
      StationState.passed => lineColor.withOpacity(0.35),
      StationState.current => lineColor,
      StationState.upcoming => t.disabledColor,
    };

    final labelStyle = switch (state) {
      StationState.passed =>
        t.textTheme.bodySmall?.copyWith(color: t.hintColor),
      StationState.current =>
        t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
      StationState.upcoming => t.textTheme.bodySmall,
    };

    // direction-aware movement independent of RTL labels
    final int dirSign = (forward ? 1 : -1) * (rtl ? -1 : 1);

    // Train x-position (inside the 100px station cell)
    final double trainDx = 50 + dirSign * 42 * trainT; // center ± 42px
    final bool faceLeft = (!forward && !rtl) || (forward && rtl);

    // Subtle bob for train
    final double bob = math.sin(animPhase * 2 * math.pi) * 1.5;

    // Chevron flow (3 chevrons drifting from current→next)
    List<Widget> _chevrons() {
      const int count = 3;
      const double spacing = 14;
      final double p = animPhase;
      final double head = (p * (count + 1)); // 0..count+1
      final List<Widget> list = [];
      for (int i = 0; i < count; i++) {
        final double k = head - i;
        final double vis = k.clamp(0, 1);
        final double alpha = (1 - (k - vis).abs()).clamp(0, 1);
        final double offset = 50 + dirSign * (18 + spacing * i + 28 * vis);
        list.add(Positioned(
          left: rtl ? null : offset,
          right: rtl ? offset : null,
          child: Opacity(
            opacity: 0.15 + 0.55 * alpha,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.rotationY(faceLeft ? math.pi : 0),
              child: const Icon(Icons.chevron_right, size: 16),
            ),
          ),
        ));
      }
      return list;
    }

    // Pulse for “next” station (concentric waves)
    Widget _nextPulse() {
      final double wave = (math.sin(animPhase * 2 * math.pi) + 1) / 2;
      final double r = 12 + 6 * wave; // radius 12..18
      return IgnorePointer(
        child: Container(
          width: r * 2,
          height: r * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: lineColor.withOpacity(0.35 + 0.25 * (1 - wave)),
              width: 2,
            ),
          ),
        ),
      );
    }

    const double nameH = 34;
    const double dotAreaH = 34;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            height: nameH,
            child: Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: labelStyle,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 100,
            height: dotAreaH,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isNextDot) Positioned(child: _nextPulse()),
                // Base dot
                Container(
                  width: state == StationState.current ? 14 : 10,
                  height: state == StationState.current ? 14 : 10,
                  decoration: BoxDecoration(
                    color: dotColor,
                    border: Border.all(
                      color: lineColor,
                      width: state == StationState.current ? 2 : 1,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: state == StationState.current
                        ? [
                            BoxShadow(
                              color: lineColor.withOpacity(0.45),
                              blurRadius: 10,
                              spreadRadius: 0.5,
                            )
                          ]
                        : null,
                  ),
                ),
                if (showTrainHere) ..._chevrons(),
                if (showTrainHere)
                  Positioned(
                    left: rtl ? null : trainDx,
                    right: rtl ? trainDx : null,
                    top: bob,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: lineColor.withOpacity(0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.rotationY(faceLeft ? math.pi : 0),
                        child: Icon(
                          Icons.directions_subway_filled,
                          size: 18,
                          color: lineColor,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (stop.transferLines.isNotEmpty) ...[
            const SizedBox(height: 2),
            SizedBox(
              height: 22,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: stop.transferLines
                      .map((l) => _TransferBadge(
                            line: l,
                            compact: true,
                            lineNameLocalized:
                                lineNameLocalized, // use passed fn
                          ))
                      .toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransferBadge extends StatelessWidget {
  const _TransferBadge({
    required this.line,
    this.compact = false,
    required this.lineNameLocalized,
  });
  final String line;
  final bool compact;
  final String Function(String) lineNameLocalized;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final color = _colorForLine(line, t);
    final pad = compact
        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 4);

    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.7)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_subway_filled,
              size: compact ? 10 : 12, color: color),
          const SizedBox(width: 4),
          Text(
            lineNameLocalized(line),
            style: t.textTheme.labelSmall?.copyWith(
              color: color,
              fontSize: compact ? 10 : null,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForLine(String line, ThemeData t) {
    switch (line.toLowerCase()) {
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
        return t.colorScheme.primary;
    }
  }
}

class _BaselinePainter extends CustomPainter {
  _BaselinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final y = size.height / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
  }

  @override
  bool shouldRepaint(covariant _BaselinePainter oldDelegate) =>
      oldDelegate.color != color;
}

// ─────────────────────────── Action banner ───────────────────────────
class _NextActionBanner extends StatelessWidget {
  final bool alight;
  final bool transfer;
  final String? transferToLineKey;

  // NEW prepare
  final bool prepare;
  final int prepareStopsAway;
  final String? prepareToLineKey;
  final String? prepareAtStation;

  // localization utils
  final bool rtl;
  final String Function(String) localizeDigits;
  final String Function(String, String) tr;
  final String Function(String) lineNameLocalized;

  const _NextActionBanner({
    required this.alight,
    required this.transfer,
    required this.transferToLineKey,
    this.prepare = false,
    this.prepareStopsAway = 0,
    this.prepareToLineKey,
    this.prepareAtStation,
    required this.rtl,
    required this.localizeDigits,
    required this.tr,
    required this.lineNameLocalized,
  });

  @override
  Widget build(BuildContext context) {
    late Color bg, border;
    late IconData icon;
    late String title, subtitle;

    if (alight) {
      bg = const Color(0xFFFFEBEE);
      border = const Color(0xFFE53935);
      icon = Icons.directions_walk_rounded;
      title = tr('Alight at next station', 'انزل في المحطة التالية');
      subtitle = tr('Get ready to exit the train', 'استعد للنزول من القطار');
    } else if (transfer) {
      bg = const Color(0xFFFFF3E0);
      border = const Color(0xFFFB8C00);
      icon = Icons.swap_horiz_rounded;
      final line = (transferToLineKey ?? '').toLowerCase();
      title = tr('Change line here', 'بدّل الخط هنا');
      subtitle =
          '${tr('to', 'إلى')} ${lineNameLocalized(line)} ${tr('line', 'الخط')}';
    } else if (prepare) {
      bg = const Color(0xFFFFF8E1); // very light amber
      border = const Color(0xFFFFC107); // amber
      icon = Icons.schedule_rounded;
      final toLine = (prepareToLineKey ?? '').toLowerCase();
      final atName = prepareAtStation ?? '-';
      final stops = prepareStopsAway > 0
          ? ' ${tr("in", "خلال")} ${localizeDigits(prepareStopsAway.toString())} ${tr("stops", "محطات")}'
          : '';
      title = tr('Get ready to change line', 'استعد لتبديل الخط');
      subtitle =
          '${tr("At", "في")} $atName • ${tr("to", "إلى")} ${lineNameLocalized(toLine)} ${tr("line", "الخط")}$stops';
    } else {
      // Fallback (shouldn’t happen)
      bg = const Color(0xFFE3F2FD);
      border = const Color(0xFF1976D2);
      icon = Icons.info_outline;
      title = tr('Info', 'معلومة');
      subtitle = '';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: border.withOpacity(.4)),
            ),
            child: Icon(icon, size: 20, color: border),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        TextStyle(color: border, fontWeight: FontWeight.w900)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.black87, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Next station card ───────────────────────────
class _NextCard extends StatelessWidget {
  const _NextCard({
    required this.title,
    required this.name,
    required this.transfers,
    required this.accent,

    // Existing chips
    required this.alightHere,
    required this.transferHere,
    required this.transferToLineKey,
    required this.rtl,

    // NEW prepare chip
    required this.prepareTransferSoon,
    required this.prepareTransferStopsAway,
    required this.prepareTransferToLineKey,
    required this.prepareAtStationName,

    // localization utils
    required this.localizeDigits,
    required this.lineNameLocalized,
    required this.tr,
  });

  final String title;
  final String name;
  final List<String> transfers;
  final Color accent;

  final bool alightHere;
  final bool transferHere;
  final String? transferToLineKey;
  final bool rtl;

  // NEW
  final bool prepareTransferSoon;
  final int prepareTransferStopsAway;
  final String? prepareTransferToLineKey;
  final String? prepareAtStationName;

  // localization utils
  final String Function(String) localizeDigits;
  final String Function(String) lineNameLocalized;
  final String Function(String, String) tr;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    final List<Widget> chips = [];
    if (alightHere) {
      chips.add(_chip(context, Icons.directions_walk_rounded,
          tr('Alight here', 'انزل هنا'), const Color(0xFFE53935)));
    } else if (transferHere) {
      final lc = (transferToLineKey ?? '').toLowerCase();
      final c = _lineColor(lc) ?? const Color(0xFFFB8C00);
      chips.add(_chip(
        context,
        Icons.swap_horiz_rounded,
        '${tr('Transfer', 'تحويل')} → ${lineNameLocalized(lc)}',
        c,
      ));
    } else if (prepareTransferSoon) {
      final lc = (prepareTransferToLineKey ?? '').toLowerCase();
      final c = _lineColor(lc) ?? const Color(0xFFFFC107);
      final stops = prepareTransferStopsAway > 0
          ? ' · ${localizeDigits(prepareTransferStopsAway.toString())}'
          : '';
      chips.add(_chip(
        context,
        Icons.schedule_rounded,
        '${tr('Prepare to transfer', 'استعد للتحويل')} → ${lineNameLocalized(lc)}$stops',
        c,
      ));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: t.cardColor,
        border: Border.all(color: t.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 6,
              height: 40,
              decoration: BoxDecoration(
                  color: accent, borderRadius: BorderRadius.circular(6)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: t.textTheme.labelMedium
                          ?.copyWith(color: t.hintColor)),
                  const SizedBox(height: 4),
                  Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (chips.isNotEmpty) Wrap(spacing: 8, children: chips),
          ]),
          if (transfers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: transfers
                  .map((l) => _TransferBadge(
                        line: l,
                        lineNameLocalized: lineNameLocalized,
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _chip(BuildContext c, IconData ic, String text, Color cMain) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: cMain.withOpacity(.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ic, size: 16, color: cMain),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: cMain, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  static Color? _lineColor(String key) {
    switch (key) {
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
    }
    return null;
  }
}
