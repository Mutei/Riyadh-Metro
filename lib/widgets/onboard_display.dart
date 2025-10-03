// lib/widgets/metro/onboard_display.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

class MetroStop {
  final String id;
  final String nameEn;
  final String nameAr;
  final bool isTransfer;
  final List<String> transferLines;

  MetroStop({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    this.isTransfer = false,
    this.transferLines = const [],
  });
}

Future<void> showOnboardDisplay(
  BuildContext context, {
  required List<MetroStop> stops,
  required int currentIndex,
  required String lineKey,
  required Color lineColor,
  String? directionNameEn,
  String? directionNameAr,
  Duration? etaToNext,
  bool isRTL = false,
  bool forward = true, // direction along the line
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
          stops: stops,
          currentIndex: currentIndex,
          lineKey: lineKey,
          lineColor: lineColor,
          directionNameEn: directionNameEn,
          directionNameAr: directionNameAr,
          etaToNext: etaToNext,
          isRTL: isRTL,
          forward: forward,
        ),
      );
    },
  );
}

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

  @override
  State<_OnboardPanel> createState() => _OnboardPanelState();
}

class _OnboardPanelState extends State<_OnboardPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))
        ..repeat();

  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerCurrent());
  }

  void _centerCurrent() {
    const itemExtent = 120.0;
    final idx = widget.currentIndex.toDouble();
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final isDark = t.brightness == Brightness.dark;

    final int nextIndex = widget.forward
        ? (widget.currentIndex + 1).clamp(0, widget.stops.length - 1)
        : (widget.currentIndex - 1).clamp(0, widget.stops.length - 1);
    final nextStop = widget.stops[nextIndex];

    final String dirTextEn = widget.directionNameEn ??
        (widget.forward
            ? 'To ${widget.stops.last.nameEn}'
            : 'To ${widget.stops.first.nameEn}');
    final String dirTextAr = widget.directionNameAr ??
        (widget.forward
            ? 'إلى ${widget.stops.last.nameAr}'
            : 'إلى ${widget.stops.first.nameAr}');

    final hasTransfers = widget.stops.any((s) => s.transferLines.isNotEmpty);
    final double timelineH = hasTransfers ? 150.0 : 120.0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 36,
                  decoration: BoxDecoration(
                    color: widget.lineColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Line ${widget.lineKey}',
                          style: t.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(widget.isRTL ? dirTextAr : dirTextEn,
                          style: t.textTheme.bodyMedium
                              ?.copyWith(color: t.hintColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (widget.etaToNext != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule, size: 18),
                      const SizedBox(width: 6),
                      Text(_formatEta(widget.etaToNext!),
                          style: t.textTheme.bodyMedium),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: timelineH,
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _BaselinePainter(
                                widget.lineColor.withOpacity(0.35)),
                          ),
                        ),
                      ),
                      ListView.builder(
                        controller: _scrollCtrl,
                        scrollDirection: Axis.horizontal,
                        itemExtent: 120,
                        itemCount: widget.stops.length,
                        itemBuilder: (context, i) {
                          final stop = widget.stops[i];
                          final isCurrent = i == widget.currentIndex;
                          final isPassed = widget.forward
                              ? i < widget.currentIndex
                              : i > widget.currentIndex;
                          final isNext = i == nextIndex;

                          return _StationColumn(
                            stop: stop,
                            lineColor: widget.lineColor,
                            state: isCurrent
                                ? StationState.current
                                : (isPassed
                                    ? StationState.passed
                                    : StationState.upcoming),
                            showTrainHere: isCurrent || isNext,
                            trainT: (isCurrent
                                ? _ctrl.value
                                : (isNext ? (1 - _ctrl.value) : 0)),
                            rtl: widget.isRTL,
                            forward: widget.forward,
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            _NextCard(
              title: widget.isRTL ? 'المحطة التالية' : 'Next station',
              name: widget.isRTL ? nextStop.nameAr : nextStop.nameEn,
              transfers: nextStop.transferLines,
              accent: widget.lineColor,
            ),
          ],
        ),
      ),
    );
  }

  static String _formatEta(Duration d) {
    if (d.inMinutes >= 1) return '${d.inMinutes} min';
    return '${d.inSeconds}s';
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
    required this.rtl,
    required this.forward,
  });

  final MetroStop stop;
  final Color lineColor;
  final StationState state;
  final bool showTrainHere;
  final double trainT;
  final bool rtl;
  final bool forward;

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
    final double trainDx = 60 + dirSign * 40 * trainT;
    final bool faceLeft = (!forward && !rtl) || (forward && rtl);

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
            child: Text(name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: labelStyle),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 100,
            height: dotAreaH,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: state == StationState.current ? 14 : 10,
                  height: state == StationState.current ? 14 : 10,
                  decoration: BoxDecoration(
                    color: dotColor,
                    border: Border.all(
                        color: lineColor,
                        width: state == StationState.current ? 2 : 1),
                    shape: BoxShape.circle,
                    boxShadow: state == StationState.current
                        ? [
                            BoxShadow(
                                color: lineColor.withOpacity(0.5),
                                blurRadius: 8)
                          ]
                        : null,
                  ),
                ),
                if (showTrainHere)
                  Positioned(
                    left: rtl ? null : trainDx,
                    right: rtl ? trainDx : null,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.rotationY(faceLeft ? math.pi : 0),
                      child: Icon(Icons.directions_subway_filled,
                          size: 18, color: lineColor),
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
                      .map((l) => _TransferBadge(line: l, compact: true))
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
  const _TransferBadge({required this.line, this.compact = false});
  final String line;
  final bool compact;

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
            line,
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

class _NextCard extends StatelessWidget {
  const _NextCard({
    required this.title,
    required this.name,
    required this.transfers,
    required this.accent,
  });

  final String title;
  final String name;
  final List<String> transfers;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: t.cardColor,
        border: Border.all(color: t.dividerColor.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Container(
              width: 6,
              height: 40,
              decoration: BoxDecoration(
                  color: accent, borderRadius: BorderRadius.circular(6))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        t.textTheme.labelMedium?.copyWith(color: t.hintColor)),
                const SizedBox(height: 4),
                Text(name,
                    style: t.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                if (transfers.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                      spacing: 6,
                      children: transfers
                          .map((l) => _TransferBadge(line: l))
                          .toList()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
