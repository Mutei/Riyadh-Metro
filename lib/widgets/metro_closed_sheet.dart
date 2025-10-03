// lib/widgets/metro_closed_sheet.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/metro_hours.dart';
import '../localization/language_constants.dart';

String t(BuildContext context, String key) {
  final s = getTranslated(context, key);
  return (s == null || s.isEmpty) ? key : s;
}

Future<void> showMetroClosedSheet(
  BuildContext context,
  DateTime nowLocal,
) async {
  final next = MetroHours.nextOpen(nowLocal);
  final until = next.difference(nowLocal);
  final nextStr = DateFormat('EEE, d MMM • h:mm a').format(next);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.subway_rounded, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t(context, "No trips available"),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "${t(context, "Metro stations are currently closed.")}\n"
                "${t(context, "Hours: Sat–Thu 5:30 AM — 12:00 AM • Fri 10:00 AM — 12:00 AM")}",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Theme.of(context).colorScheme.surfaceVariant,
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${t(context, "Opens in")} ${MetroHours.untilString(until)}",
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${t(context, "Next opening")}: $nextStr",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t(context, "Got it")),
            ),
          ],
        ),
      );
    },
  );
}
