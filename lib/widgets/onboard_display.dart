import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/metro_train_marker_preferences.dart';
import '../services/onboard_display_preferences.dart';

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

/// The live portion of an onboard display. MainScreen publishes a replacement
/// whenever trip tracking advances, so an already-open sheet stays current.
class OnboardDisplayData {
  const OnboardDisplayData({
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
    this.alightHere = false,
    this.transferHere = false,
    this.transferToLineKey,
    this.prepareTransferSoon = false,
    this.prepareTransferStopsAway = 0,
    this.prepareTransferToLineKey,
    this.prepareAtStationName,
    this.segmentProgress = .35,
    this.speedKmh,
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
  final bool alightHere;
  final bool transferHere;
  final String? transferToLineKey;
  final bool prepareTransferSoon;
  final int prepareTransferStopsAway;
  final String? prepareTransferToLineKey;
  final String? prepareAtStationName;
  final double segmentProgress;
  final double? speedKmh;
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
  ValueListenable<OnboardDisplayData>? liveData,
}) async {
  assert(stops.isNotEmpty);
  currentIndex = currentIndex.clamp(0, stops.length - 1);
  final initialData = OnboardDisplayData(
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
    fullLineStops: fullLineStops,
    autoBuildSegmentFromFull: autoBuildSegmentFromFull,
    nextLinePreviewStops: nextLinePreviewStops,
    nextLineKey: nextLineKey,
    nextLineColor: nextLineColor,
    nextDirectionNameEn: nextDirectionNameEn,
    nextDirectionNameAr: nextDirectionNameAr,
    alightHere: alightHere,
    transferHere: transferHere,
    transferToLineKey: transferToLineKey,
    prepareTransferSoon: prepareTransferSoon,
    prepareTransferStopsAway: prepareTransferStopsAway,
    prepareTransferToLineKey: prepareTransferToLineKey,
    prepareAtStationName: prepareAtStationName,
  );
  final displayStyle = await OnboardDisplayPreferences.load();
  final trainMarkerStyle = await MetroTrainMarkerPreferences.load();
  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final isDark = theme.brightness == Brightness.dark;
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [Color(0xFF0B1522), Color(0xFF101D2B)]
                : [theme.scaffoldBackgroundColor, theme.colorScheme.surface],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: theme.dividerColor.withValues(alpha: .42)),
        ),
        child: liveData == null
            ? _OnboardDisplayBody(
                data: initialData,
                displayStyle: displayStyle,
                trainMarkerStyle: trainMarkerStyle,
              )
            : ValueListenableBuilder<OnboardDisplayData>(
                valueListenable: liveData,
                builder: (_, data, __) => _OnboardDisplayBody(
                  data: data,
                  displayStyle: displayStyle,
                  trainMarkerStyle: trainMarkerStyle,
                ),
              ),
      );
    },
  );
}

class _OnboardDisplayBody extends StatelessWidget {
  const _OnboardDisplayBody({
    required this.data,
    required this.displayStyle,
    required this.trainMarkerStyle,
  });

  final OnboardDisplayData data;
  final OnboardDisplayStyle displayStyle;
  final MetroTrainMarkerStyle trainMarkerStyle;

  @override
  Widget build(BuildContext context) {
    final panel = switch (displayStyle) {
      OnboardDisplayStyle.stationPulse => _OnboardPanel.fromData(data),
      OnboardDisplayStyle.originalMotion => _OriginalMotionPanel(
          data: data,
          trainMarkerStyle: trainMarkerStyle,
        ),
      OnboardDisplayStyle.trackFocus => _TrackFocusPanel(
          data: data,
          trainMarkerStyle: trainMarkerStyle,
        ),
      OnboardDisplayStyle.liveCarriage => _LiveCarriagePanel(
          data: data,
          trainMarkerStyle: trainMarkerStyle,
        ),
    };
    return Directionality(
      textDirection: data.isRTL ? TextDirection.rtl : TextDirection.ltr,
      child: panel,
    );
  }
}

enum _ViewMode { segment, fullLine, nextLine }

String _motionTrainAsset(
  String lineKey,
  MetroTrainMarkerStyle markerStyle, {
  bool forward = true,
}) {
  if (markerStyle == MetroTrainMarkerStyle.classic) {
    return 'assets/markers/metro_train_topdown.png';
  }
  final key = lineKey.toLowerCase();
  const supported = {'yellow', 'blue', 'red', 'purple', 'orange', 'green'};
  if (markerStyle == MetroTrainMarkerStyle.directional3d &&
      supported.contains(key)) {
    final direction = forward ? 'e' : 'w';
    return 'assets/markers/directional/metro_train_3d_${key}_$direction.png';
  }
  return supported.contains(key)
      ? 'assets/markers/metro_train_$key.png'
      : 'assets/markers/metro_train_topdown.png';
}

String _motionStationName(OnboardDisplayData data, MetroStop stop) =>
    data.isRTL ? stop.nameAr : stop.nameEn;

List<MetroStop> _upcomingStops(OnboardDisplayData data) {
  if (data.stops.isEmpty) return const [];
  final current = data.currentIndex.clamp(0, data.stops.length - 1).toInt();
  final ordered = data.forward
      ? data.stops.sublist(current)
      : data.stops.sublist(0, current + 1).reversed.toList();
  if (ordered.length <= 1) return ordered;
  return ordered.skip(1).toList();
}

String _motionEta(Duration? eta, bool rtl) {
  if (eta == null) return '--';
  final minutes = math.max(1, (eta.inSeconds / 60).ceil());
  return rtl ? '$minutes دقيقة' : '$minutes min';
}

class _MotionEtaText extends StatefulWidget {
  const _MotionEtaText({
    required this.eta,
    required this.rtl,
    required this.style,
  });

  final Duration? eta;
  final bool rtl;
  final TextStyle? style;

  @override
  State<_MotionEtaText> createState() => _MotionEtaTextState();
}

class _MotionEtaTextState extends State<_MotionEtaText> {
  Timer? _timer;
  DateTime? _updatedAt;
  Duration? _base;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant _MotionEtaText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eta != widget.eta) _reset();
  }

  void _reset() {
    _base = widget.eta;
    _updatedAt = widget.eta == null ? null : DateTime.now();
    _timer?.cancel();
    if (widget.eta != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  Duration? get _remaining {
    if (_base == null || _updatedAt == null) return null;
    final value = _base! - DateTime.now().difference(_updatedAt!);
    return value.isNegative ? Duration.zero : value;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        _motionEta(_remaining, widget.rtl),
        style: widget.style,
      );
}

class _MotionPanelShell extends StatelessWidget {
  const _MotionPanelShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .72,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
          child: child,
        ),
      ),
    );
  }
}

class _MotionHeader extends StatelessWidget {
  const _MotionHeader({
    required this.data,
    this.showSpeed = false,
  });

  final OnboardDisplayData data;
  final bool showSpeed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: .64);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 58,
          decoration: BoxDecoration(
            color: data.lineColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: data.lineColor.withValues(alpha: .35),
                blurRadius: 16,
              ),
            ],
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${data.isRTL ? 'الخط' : 'LINE'} ${data.lineKey.toUpperCase()}',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: data.isRTL ? 0 : .8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.isRTL
                    ? (data.directionNameAr ?? '')
                    : (data.directionNameEn ?? ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (showSpeed) ...[
          Icon(Icons.speed_rounded, size: 20, color: muted),
          const SizedBox(width: 5),
          Text(
            data.speedKmh == null
                ? '-- km/h'
                : '${data.speedKmh!.round()} km/h',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 14),
        ],
        Icon(Icons.schedule_rounded, color: muted),
        const SizedBox(width: 6),
        _MotionEtaText(
          eta: data.etaToNext,
          rtl: data.isRTL,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _MotionNextCard extends StatelessWidget {
  const _MotionNextCard({required this.data});

  final OnboardDisplayData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upcoming = _upcomingStops(data);
    final next = upcoming.isNotEmpty
        ? upcoming.first
        : data.stops[data.currentIndex.clamp(0, data.stops.length - 1)];
    final action = data.transferHere
        ? (data.isRTL ? 'غيّر الخط هنا' : 'Change line here')
        : data.alightHere
            ? (data.isRTL ? 'انزل في المحطة التالية' : 'Alight at next station')
            : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .32),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withValues(alpha: .6)),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 54,
            decoration: BoxDecoration(
              color: data.lineColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action ?? (data.isRTL ? 'المحطة التالية' : 'NEXT STATION'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .58),
                    fontWeight: FontWeight.w800,
                    letterSpacing: data.isRTL ? 0 : 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _motionStationName(data, next),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OriginalMotionPanel extends StatelessWidget {
  const _OriginalMotionPanel({
    required this.data,
    required this.trainMarkerStyle,
  });

  final OnboardDisplayData data;
  final MetroTrainMarkerStyle trainMarkerStyle;

  @override
  Widget build(BuildContext context) {
    final upcoming = _upcomingStops(data).take(3).toList();
    return _MotionPanelShell(
      child: Column(
        children: [
          const _SheetHandle(),
          const SizedBox(height: 20),
          _MotionHeader(data: data),
          const SizedBox(height: 26),
          _AssetTrainTrack(
            data: data,
            stops: upcoming,
            markerStyle: trainMarkerStyle,
            compact: true,
          ),
          const SizedBox(height: 22),
          _MotionNextCard(data: data),
        ],
      ),
    );
  }
}

class _TrackFocusPanel extends StatelessWidget {
  const _TrackFocusPanel({
    required this.data,
    required this.trainMarkerStyle,
  });

  final OnboardDisplayData data;
  final MetroTrainMarkerStyle trainMarkerStyle;

  @override
  Widget build(BuildContext context) {
    final upcoming = _upcomingStops(data).take(3).toList();
    return _MotionPanelShell(
      child: Column(
        children: [
          const _SheetHandle(),
          const SizedBox(height: 20),
          _MotionHeader(data: data),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 18, 8, 14),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: .25),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: .55),
              ),
            ),
            child: _AssetTrainTrack(
              data: data,
              stops: upcoming,
              markerStyle: trainMarkerStyle,
              showTimes: true,
            ),
          ),
          const SizedBox(height: 18),
          _SegmentProgress(data: data, stopCount: upcoming.length),
          const SizedBox(height: 18),
          _MotionNextCard(data: data),
        ],
      ),
    );
  }
}

class _LiveCarriagePanel extends StatelessWidget {
  const _LiveCarriagePanel({
    required this.data,
    required this.trainMarkerStyle,
  });

  final OnboardDisplayData data;
  final MetroTrainMarkerStyle trainMarkerStyle;

  @override
  Widget build(BuildContext context) {
    final upcoming = _upcomingStops(data).take(3).toList();
    return _MotionPanelShell(
      child: Column(
        children: [
          const _SheetHandle(),
          const SizedBox(height: 20),
          _MotionHeader(data: data, showSpeed: true),
          const SizedBox(height: 26),
          _CarriageTrack(
            data: data,
            stops: upcoming,
            markerStyle: trainMarkerStyle,
          ),
          const SizedBox(height: 24),
          _MotionNextCard(data: data),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .24),
          borderRadius: BorderRadius.circular(9),
        ),
      );
}

class _AssetTrainTrack extends StatelessWidget {
  const _AssetTrainTrack({
    required this.data,
    required this.stops,
    required this.markerStyle,
    this.compact = false,
    this.showTimes = false,
  });

  final OnboardDisplayData data;
  final List<MetroStop> stops;
  final MetroTrainMarkerStyle markerStyle;
  final bool compact;
  final bool showTimes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = math.max(1, stops.length);
    final totalMinutes = math.max(1, (data.etaToNext?.inSeconds ?? 60) ~/ 60);
    return SizedBox(
      height: compact ? 150 : 188,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final nodeY = compact ? 84.0 : 108.0;
          final positions = List.generate(
            count,
            (i) =>
                count == 1 ? width * .5 : 30 + (width - 60) * i / (count - 1),
          );
          final firstNode = positions.first;
          final trainX = (firstNode * data.segmentProgress.clamp(0.0, 1.0))
              .clamp(6.0, width - 54.0)
              .toDouble();
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 22,
                right: 22,
                top: nodeY,
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
              Positioned(
                left: 22,
                top: nodeY,
                width: math.max(0.0, trainX - 5).toDouble(),
                child: Container(
                  height: 5,
                  color: data.lineColor.withValues(alpha: .78),
                ),
              ),
              for (var i = 0; i < positions.length; i++) ...[
                Positioned(
                  left: positions[i] - 45,
                  top: 0,
                  width: 90,
                  child: Text(
                    _motionStationName(data, stops[i]),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Positioned(
                  left: positions[i] - 11,
                  top: nodeY - 9,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: data.lineColor, width: 4),
                    ),
                  ),
                ),
                if (showTimes)
                  Positioned(
                    left: positions[i] - 35,
                    top: nodeY + 24,
                    width: 70,
                    child: Text(
                      '${math.max(1, (totalMinutes * (i + 1) / count).ceil())} min',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
              AnimatedPositioned(
                duration: const Duration(milliseconds: 850),
                curve: Curves.easeOutCubic,
                left: trainX,
                top: nodeY - (compact ? 24 : 30),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: compact ? 54 : 68,
                      height: compact ? 54 : 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: data.lineColor.withValues(alpha: .12),
                        boxShadow: [
                          BoxShadow(
                            color: data.lineColor.withValues(alpha: .32),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                    ),
                    Transform.rotate(
                      angle: markerStyle == MetroTrainMarkerStyle.directional3d
                          ? 0
                          : math.pi / 2,
                      child: Image.asset(
                        _motionTrainAsset(
                          data.lineKey,
                          markerStyle,
                          forward: data.forward,
                        ),
                        width: compact ? 46 : 58,
                        height: compact ? 46 : 58,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SegmentProgress extends StatelessWidget {
  const _SegmentProgress({required this.data, required this.stopCount});

  final OnboardDisplayData data;
  final int stopCount;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: data.segmentProgress.clamp(0.0, 1.0),
                minHeight: 6,
                color: data.lineColor,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .15),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            '$stopCount ${data.isRTL ? 'محطات' : 'stations'}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      );
}

class _CarriageTrack extends StatelessWidget {
  const _CarriageTrack({
    required this.data,
    required this.stops,
    required this.markerStyle,
  });

  final OnboardDisplayData data;
  final List<MetroStop> stops;
  final MetroTrainMarkerStyle markerStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = math.max(1, stops.length);
    return SizedBox(
      height: 205,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final positions = List.generate(
            count,
            (i) =>
                count == 1 ? width * .5 : 35 + (width - 70) * i / (count - 1),
          );
          final trainWidth = math.min(230.0, width * .52);
          final targetX = positions.first;
          final trainCenter = (targetX * data.segmentProgress.clamp(0.0, 1.0))
              .clamp(trainWidth / 2, width - trainWidth / 2)
              .toDouble();
          return Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 117,
                child: Container(height: 5, color: data.lineColor),
              ),
              for (var i = 0; i < positions.length; i++) ...[
                Positioned(
                  left: positions[i] - 2,
                  top: 36,
                  child: Container(
                    width: 4,
                    height: 82,
                    decoration: BoxDecoration(
                      color: data.lineColor.withValues(alpha: .62),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Positioned(
                  left: positions[i] - 40,
                  top: 135,
                  width: 80,
                  child: Text(
                    _motionStationName(data, stops[i]).toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
              AnimatedPositioned(
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                left: trainCenter - trainWidth / 2,
                top: 67,
                child: markerStyle == MetroTrainMarkerStyle.directional3d
                    ? SizedBox(
                        width: trainWidth,
                        height: 72,
                        child: Image.asset(
                          _motionTrainAsset(
                            data.lineKey,
                            markerStyle,
                            forward: data.forward,
                          ),
                          fit: BoxFit.contain,
                        ),
                      )
                    : _SideMetroTrain(
                        color: data.lineColor,
                        width: trainWidth,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SideMetroTrain extends StatelessWidget {
  const _SideMetroTrain({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: 58,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: .9),
              color,
              const Color(0xFFD7DDE2),
            ],
            stops: const [0, .72, 1],
          ),
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(9),
            right: Radius.circular(28),
          ),
          border: Border.all(color: Colors.white.withValues(alpha: .65)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: .4),
              blurRadius: 18,
              offset: const Offset(-10, 0),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            for (var i = 0; i < 6; i++) ...[
              Expanded(
                child: Container(
                  height: 19,
                  decoration: BoxDecoration(
                    color: const Color(0xFF101820),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            const SizedBox(width: 17),
          ],
        ),
      );
}

class _OnboardPanel extends StatefulWidget {
  _OnboardPanel.fromData(OnboardDisplayData data)
      : this(
          stops: data.stops,
          currentIndex: data.currentIndex,
          lineKey: data.lineKey,
          lineColor: data.lineColor,
          directionNameEn: data.directionNameEn,
          directionNameAr: data.directionNameAr,
          etaToNext: data.etaToNext,
          isRTL: data.isRTL,
          forward: data.forward,
          nextStationOverride: data.nextStationOverride,
          fullLineStops: data.fullLineStops,
          autoBuildSegmentFromFull: data.autoBuildSegmentFromFull,
          nextLinePreviewStops: data.nextLinePreviewStops,
          nextLineKey: data.nextLineKey,
          nextLineColor: data.nextLineColor,
          nextDirectionNameEn: data.nextDirectionNameEn,
          nextDirectionNameAr: data.nextDirectionNameAr,
          alightHere: data.alightHere,
          transferHere: data.transferHere,
          transferToLineKey: data.transferToLineKey,
          prepareTransferSoon: data.prepareTransferSoon,
          prepareTransferStopsAway: data.prepareTransferStopsAway,
          prepareTransferToLineKey: data.prepareTransferToLineKey,
          prepareAtStationName: data.prepareAtStationName,
        );

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
  Timer? _etaTicker;
  Duration? _etaAtUpdate;
  DateTime? _etaUpdatedAt;

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
      final minutes = math.max(1, (d.inSeconds / 60).ceil());
      final txt = '$minutes ${_t("min", "دقيقة")}';
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
    _resetEta(widget.etaToNext);
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerCurrent());
  }

  @override
  void didUpdateWidget(covariant _OnboardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.etaToNext != widget.etaToNext) {
      _resetEta(widget.etaToNext);
    }

    final stationChanged = oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.nextStationOverride != widget.nextStationOverride ||
        oldWidget.lineKey != widget.lineKey ||
        oldWidget.forward != widget.forward;
    if (stationChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _centerCurrent();
      });
    }
  }

  void _resetEta(Duration? eta) {
    _etaAtUpdate = eta;
    _etaUpdatedAt = eta == null ? null : DateTime.now();
    _etaTicker?.cancel();
    if (eta != null) {
      _etaTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  Duration? get _displayEta {
    final eta = _etaAtUpdate;
    final updatedAt = _etaUpdatedAt;
    if (eta == null || updatedAt == null) return null;
    final elapsed = DateTime.now().difference(updatedAt);
    final remaining = eta - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  _ViewMode _initialMode() {
    if (widget.fullLineStops != null && widget.autoBuildSegmentFromFull) {
      return _ViewMode.segment;
    }
    return _ViewMode.segment;
  }

  void _centerCurrent() {
    if (!_scrollCtrl.hasClients) return;
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
    _etaTicker?.cancel();
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

    final remainingStops = widget.forward
        ? math.max(0, activeStops.length - 1 - currentIdx)
        : math.max(0, currentIdx);
    final onSurface = t.colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: isDark ? .68 : .62);
    final lineSurface = Color.alphaBlend(
      lineColor.withValues(alpha: isDark ? .25 : .13),
      t.colorScheme.surface,
    );

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

            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    lineSurface,
                    lineColor.withValues(alpha: isDark ? .13 : .08),
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: lineColor.withValues(alpha: .42)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: lineColor,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: lineColor.withValues(alpha: .28),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.directions_subway_rounded,
                      color: Colors.white,
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t('ACTIVE LINE', 'الخط الحالي'),
                          style: t.textTheme.labelSmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_t("Line", "الخط")} ${_lineNameLocalized(lineKey)}',
                          style: t.textTheme.titleLarge?.copyWith(
                            color: onSurface,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.25,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _rtl ? dirTextAr : dirTextEn,
                          style: t.textTheme.bodyMedium?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (_displayEta != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: t.colorScheme.surface.withValues(alpha: .72),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _t('ETA', 'الوصول'),
                            style: t.textTheme.labelSmall?.copyWith(
                              color: muted,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _fmtEta(_displayEta!),
                            style: t.textTheme.titleSmall?.copyWith(
                              color: onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
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

            const SizedBox(height: 14),

            // Next station remains the primary actionable item.
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
            const SizedBox(height: 12),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 8),
              decoration: BoxDecoration(
                color: t.colorScheme.surfaceContainerHighest
                    .withValues(alpha: isDark ? .46 : .68),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: t.dividerColor.withValues(alpha: isDark ? .36 : .5),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color:
                              lineColor.withValues(alpha: isDark ? .24 : .14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.alt_route_rounded,
                          size: 17,
                          color: lineColor,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _t('ROUTE PROGRESS', 'تقدم المسار'),
                          style: t.textTheme.labelMedium?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .9,
                          ),
                        ),
                      ),
                      Text(
                        '${_localizeDigits(remainingStops.toString())} ${_t('stops left', 'محطات متبقية')}',
                        style: t.textTheme.labelSmall?.copyWith(
                          color: onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AnimatedBuilder(
                    animation: _curve,
                    builder: (context, _) => _PulseRouteSpine(
                      stops: activeStops,
                      currentIndex: currentIdx,
                      nextIndex: nextIdx,
                      forward: widget.forward,
                      isRTL: _rtl,
                      lineColor: lineColor,
                      pulse: _curve.value,
                      tr: _t,
                      lineNameLocalized: _lineNameLocalized,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum StationState { passed, current, upcoming }

class _PulseRouteSpine extends StatelessWidget {
  const _PulseRouteSpine({
    required this.stops,
    required this.currentIndex,
    required this.nextIndex,
    required this.forward,
    required this.isRTL,
    required this.lineColor,
    required this.pulse,
    required this.tr,
    required this.lineNameLocalized,
  });

  final List<MetroStop> stops;
  final int currentIndex;
  final int nextIndex;
  final bool forward;
  final bool isRTL;
  final Color lineColor;
  final double pulse;
  final String Function(String, String) tr;
  final String Function(String) lineNameLocalized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rowHeight = 64.0;
    final height = math.min(260.0, stops.length * rowHeight).toDouble();

    return SizedBox(
      height: height,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        itemCount: stops.length,
        itemBuilder: (context, index) {
          final stop = stops[index];
          final isCurrent = index == currentIndex;
          final isNext = index == nextIndex;
          final isPassed =
              forward ? index < currentIndex : index > currentIndex;
          final isLast = index == stops.length - 1;
          final label = isRTL ? stop.nameAr : stop.nameEn;
          final textColor = (isCurrent || isNext)
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurface.withValues(alpha: .72);
          final lineBefore = isPassed || isCurrent;
          final lineAfter = isPassed;

          final spine = SizedBox(
            width: 48,
            height: rowHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (index > 0)
                  Positioned(
                    top: 0,
                    width: 3,
                    height: rowHeight / 2,
                    child: ColoredBox(
                      color: lineBefore
                          ? lineColor
                          : lineColor.withValues(alpha: .24),
                    ),
                  ),
                if (!isLast)
                  Positioned(
                    bottom: 0,
                    width: 3,
                    height: rowHeight / 2,
                    child: ColoredBox(
                      color: lineAfter
                          ? lineColor
                          : lineColor.withValues(alpha: .24),
                    ),
                  ),
                if (isCurrent)
                  Container(
                    width: 42 + (pulse * 8),
                    height: 42 + (pulse * 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: lineColor.withValues(alpha: .22 + pulse * .22),
                        width: 2,
                      ),
                    ),
                  ),
                Container(
                  width: isCurrent ? 34 : (isNext ? 24 : 16),
                  height: isCurrent ? 34 : (isNext ? 24 : 16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCurrent || isPassed
                        ? lineColor
                        : theme.colorScheme.surface,
                    border: Border.all(
                      color: lineColor,
                      width: isCurrent ? 3 : 2,
                    ),
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                              color: lineColor.withValues(alpha: .45),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Container(
                      width: isCurrent ? 13 : (isNext ? 8 : 0),
                      height: isCurrent ? 13 : (isNext ? 8 : 0),
                      decoration: BoxDecoration(
                        color: (isCurrent || isNext)
                            ? Colors.white
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );

          final details = Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: textColor,
                      fontWeight: isCurrent || isNext
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                  if (isNext) ...[
                    const SizedBox(height: 2),
                    Text(
                      tr('Next station', 'المحطة التالية'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: lineColor,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .45,
                      ),
                    ),
                  ] else if (stop.transferLines.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: stop.transferLines
                          .map((line) => _TransferBadge(
                                line: line,
                                compact: true,
                                lineNameLocalized: lineNameLocalized,
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: isRTL ? [details, spine] : [spine, details],
          );
        },
      ),
    );
  }
}

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
    final isDark = t.brightness == Brightness.dark;

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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Color.alphaBlend(
          accent.withValues(alpha: isDark ? .10 : .055),
          t.colorScheme.surface,
        ),
        border: Border.all(color: accent.withValues(alpha: .34)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? .17 : .06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: .3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Colors.white,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: t.textTheme.labelSmall?.copyWith(
                        color: t.colorScheme.onSurface.withValues(alpha: .62),
                        fontWeight: FontWeight.w800,
                        letterSpacing: .9,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
          if (transfers.isNotEmpty) ...[
            const SizedBox(height: 12),
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
