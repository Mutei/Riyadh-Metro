// lib/widgets/route_options_sheet.dart
import 'package:flutter/material.dart';

import '../classes/route_option.dart';
import '../localization/language_constants.dart';
import '../services/trip_analytics_service.dart';
import '../constants/colors.dart'; // <-- NEW: for AppColors.kDarkBackgroundColor
import 'all_metro_lines.dart';

class RouteOptionsSheet extends StatefulWidget {
  final List<RouteOption> options;
  final Map<RouteOption, TripTimeEstimate> historicalTimes;
  final String destLabel;
  final String Function(String key) cap;
  final void Function(RouteOption r) onPick;

  const RouteOptionsSheet({
    super.key,
    required this.options,
    this.historicalTimes = const {},
    required this.destLabel,
    required this.cap,
    required this.onPick,
  });

  @override
  State<RouteOptionsSheet> createState() => _RouteOptionsSheetState();
}

class _RouteOptionsSheetState extends State<RouteOptionsSheet> {
  bool _showAll = false;

  String _fmtDur(double s) {
    final d = Duration(seconds: s.round());
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  List<String> _guideCheckpoints(RouteOption route) {
    final checkpoints = <String>[];
    void addCheckpoint(String nodeId) {
      final stationName = route.nodes[nodeId]?.name.trim() ?? '';
      if (stationName.isEmpty ||
          (checkpoints.isNotEmpty &&
              checkpoints.last.toLowerCase() == stationName.toLowerCase())) {
        return;
      }
      checkpoints.add(stationName);
    }

    String? previousLine;
    String? lastMetroDestination;
    for (var index = 0; index < route.edgesInOrder.length; index++) {
      final edge = route.edgesInOrder[index];
      if (edge.kind != 'metro') continue;
      if (previousLine == null || previousLine != edge.lineKey) {
        addCheckpoint(route.nodeIds[index]);
      }
      previousLine = edge.lineKey;
      lastMetroDestination = route.nodeIds[index + 1];
    }
    if (lastMetroDestination != null) addCheckpoint(lastMetroDestination);
    return checkpoints;
  }

  Widget _lineChip(BuildContext context, String key) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = metroLineColors[key] ?? cs.secondary;
    final bool isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(isDark ? .22 : .15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.directions_subway_filled, size: 16, color: c),
          const SizedBox(width: 4),
          Text(
            widget.cap(key),
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    final onSurface = cs.onSurface;
    final onSurfaceSubtle = onSurface.withOpacity(0.65);
    final outline = cs.outline;
    final outlineVariant = cs.outlineVariant;

    // ✅ Use your custom dark background; keep Material surface in light mode
    final bgColor = isDark ? AppColors.kDarkBackgroundColor : cs.surface;

    if (widget.options.isEmpty) {
      return SafeArea(
        child: Container(
          color: bgColor,
          padding: const EdgeInsets.all(16),
          child: Text(
            getTranslated(context, 'No routes found'),
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    final visible = _showAll ? widget.options : widget.options.take(2).toList();

    return SafeArea(
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: onSurface.withOpacity(0.24),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${getTranslated(context, 'Choose your route')}\n${getTranslated(context, 'To')} ${widget.destLabel}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: visible.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: outlineVariant),
                itemBuilder: (_, i) {
                  final r = visible[i];
                  final historicalTime = widget.historicalTimes[r];
                  final checkpoints = _guideCheckpoints(r);
                  final displayedSeconds =
                      historicalTime?.averageSeconds ?? r.totalSeconds.round();
                  final eta = DateTime.now().add(
                    Duration(seconds: displayedSeconds),
                  );

                  return Container(
                    decoration: BoxDecoration(
                      color: i == 0
                          ? cs.primary.withOpacity(isDark ? .14 : .06)
                          : cs.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: i == 0
                            ? cs.primary.withOpacity(.45)
                            : outlineVariant,
                        width: i == 0 ? 1.4 : 1,
                      ),
                    ),
                    child: ListTile(
                      tileColor: Colors.transparent,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      title: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(isDark ? .22 : .12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: cs.primary.withOpacity(.35)),
                            ),
                            child: Text(
                              _fmtDur(displayedSeconds.toDouble()),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '• ${getTranslated(context, 'ETA')} '
                            '${TimeOfDay.fromDateTime(eta).format(context)}',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: onSurfaceSubtle),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (checkpoints.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 7),
                                child: Text(
                                  '${getTranslated(context, 'Route via')} '
                                  '${checkpoints.join(' • ')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: onSurfaceSubtle,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            if (historicalTime != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 7),
                                child: Text(
                                  '${getTranslated(context, 'Recorded average')} · '
                                  '${historicalTime.sampleCount} '
                                  '${getTranslated(context, 'completed trips')}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white10
                                        : cs.surfaceVariant,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: outline),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.directions_walk,
                                          size: 16, color: onSurface),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${r.walkMeters.toStringAsFixed(0)} '
                                        '${getTranslated(context, 'm')} '
                                        '${getTranslated(context, 'walk')}',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: onSurface),
                                      ),
                                    ],
                                  ),
                                ),
                                ...r.lineSequence
                                    .map((k) => _lineChip(context, k)),
                                if (r.transfers > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white10
                                          : cs.surfaceVariant,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: outline),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.swap_horiz_rounded,
                                            size: 16, color: onSurface),
                                        const SizedBox(width: 4),
                                        Text(
                                          r.transfers == 1
                                              ? '1 ${getTranslated(context, 'transfer')}'
                                              : '${r.transfers} ${getTranslated(context, 'transfers')}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(color: onSurface),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      onTap: () => widget.onPick(r),
                    ),
                  );
                },
              ),
            ),
            if (!_showAll && widget.options.length > 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _showAll = true),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text(
                      '${getTranslated(context, 'Show more routes')} (${widget.options.length - 2})',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.primary,
                      side: BorderSide(color: cs.primary.withOpacity(.45)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
