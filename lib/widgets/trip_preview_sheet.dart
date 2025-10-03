import 'package:flutter/material.dart';
import '../widgets/main_screen_widgets/mode_icon.dart';
import '../localization/language_constants.dart';

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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(100))),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(title,
                        textAlign: TextAlign.start,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.more_vert_rounded)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(fromLabel,
                    style: const TextStyle(
                        color: Colors.black54, fontSize: 12.5, height: 1.2)),
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
                        Text(getTranslated(context, 'Start'),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black45)),
                        const SizedBox(height: 4),
                        Text(_fmtTime(context, start),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(getTranslated(context, 'Arrival'),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black45)),
                        const SizedBox(height: 4),
                        Text(_fmtTime(context, arrival),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
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
                  final bg = m.chipColor?.withOpacity(0.15) ??
                      Colors.black.withOpacity(0.06);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: (m.chipColor ?? Colors.black12)
                              .withOpacity(0.30)),
                    ),
                    child: Row(
                      children: [
                        Icon(m.icon, size: 18, color: m.chipColor),
                        const SizedBox(width: 6),
                        Text(m.label,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            )),
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
                    dense: true, leading: Icon(icon), title: Text(steps[i]));
              },
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: steps.length,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
