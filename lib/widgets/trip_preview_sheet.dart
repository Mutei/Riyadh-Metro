// lib/widgets/trip_preview_sheet.dart
import 'package:flutter/material.dart';
import '../widgets/main_screen_widgets/mode_icon.dart';
import '../localization/language_constants.dart';
import '../constants/colors.dart'; // <-- for AppColors.kDarkBackgroundColor

class TripPreviewSheet extends StatelessWidget {
  final String title;
  final String fromLabel;
  final DateTime start;
  final DateTime arrival;
  final List<ModeIcon> modeIcons;
  final List<String> steps;

  const TripPreviewSheet({
    super.key,
    required this.title,
    required this.fromLabel,
    required this.start,
    required this.arrival,
    required this.modeIcons,
    required this.steps,
  });

  String _fmtTime(BuildContext ctx, DateTime t) =>
      TimeOfDay.fromDateTime(t).format(ctx);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? AppColors.kDarkBackgroundColor : cs.surface;
    final onSurface = cs.onSurface;
    final onSurfaceSubtle = onSurface.withOpacity(0.65);
    final hairline = cs.outlineVariant;

    return SafeArea(
      top: false,
      child: Container(
        color: bgColor, // ✅ dark-mode aware background
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: onSurface.withOpacity(0.24), // drag handle
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.start,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: Icon(Icons.more_vert_rounded, color: onSurface),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  fromLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: onSurfaceSubtle,
                    height: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          getTranslated(context, 'Start'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: onSurfaceSubtle,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fmtTime(context, start),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          getTranslated(context, 'Arrival'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: onSurfaceSubtle,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fmtTime(context, arrival),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 38,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemBuilder: (_, i) {
                  final m = modeIcons[i];
                  final chipBorderColor =
                      (m.chipColor ?? onSurface).withOpacity(0.30);
                  final chipBg = m.chipColor != null
                      ? m.chipColor!.withOpacity(isDark ? 0.18 : 0.12)
                      : (isDark ? Colors.white10 : cs.surfaceVariant);

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: chipBorderColor),
                    ),
                    child: Row(
                      children: [
                        Icon(m.icon, size: 18, color: m.chipColor ?? onSurface),
                        const SizedBox(width: 6),
                        Text(
                          m.label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: onSurface,
                          ),
                        ),
                      ],
                    ),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemCount: modeIcons.length,
              ),
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemBuilder: (_, i) {
                final isFirst = i == 0;
                final isLast = i == steps.length - 1;
                final IconData icon = isFirst
                    ? Icons.directions_walk
                    : (isLast
                        ? Icons.flag_rounded
                        : Icons.directions_subway_filled);
                return ListTile(
                  dense: true,
                  iconColor: onSurface,
                  textColor: onSurface,
                  tileColor: Colors.transparent, // keep sheet bg visible
                  leading: Icon(icon),
                  title: Text(
                    steps[i],
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: onSurface,
                    ),
                  ),
                );
              },
              separatorBuilder: (_, __) => Divider(height: 1, color: hairline),
              itemCount: steps.length,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
