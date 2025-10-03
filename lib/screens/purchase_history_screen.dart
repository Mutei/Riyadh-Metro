// lib/screens/purchase_history_screen.dart
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../constants/colors.dart';
import '../localization/language_constants.dart';

enum TicketClass { regular, firstClass }

class _TicketRecord {
  final String id;
  final String productId;
  final TicketClass klass;
  final String title;
  final int priceSar;
  final String? purchasedAtStr; // "M/d/yyyy"
  final String? activatedAtStr; // "M/d/yyyy HH:mm"
  final String? expiresAtStr; // "M/d/yyyy HH:mm"
  final bool activated;
  final bool expired;
  final DateTime? purchasedAt;
  final DateTime? activatedAt;
  final DateTime? expiresAt;

  _TicketRecord({
    required this.id,
    required this.productId,
    required this.klass,
    required this.title,
    required this.priceSar,
    required this.purchasedAtStr,
    required this.activatedAtStr,
    required this.expiresAtStr,
    required this.activated,
    required this.expired,
    required this.purchasedAt,
    required this.activatedAt,
    required this.expiresAt,
  });

  // --- parsing helpers (compatible with your existing DB strings) ---
  static String _s(dynamic v) => v is String ? v : '';
  static int _i(dynamic v) => v is num ? v.toInt() : 0;
  static bool _b(dynamic v) => v == true;

  static DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final parts = s.split(' ');
      final d = parts[0].split('/');
      if (d.length == 3) {
        final m = int.tryParse(d[0]);
        final dd = int.tryParse(d[1]);
        final y = int.tryParse(d[2]);
        int hh = 0, mm = 0;
        if (parts.length > 1) {
          final t = parts[1].split(':');
          if (t.length >= 2) {
            hh = int.tryParse(t[0]) ?? 0;
            mm = int.tryParse(t[1]) ?? 0;
          }
        }
        if (m != null && dd != null && y != null) {
          return DateTime(y, m, dd, hh, mm);
        }
      }
    } catch (_) {}
    return null;
  }

  factory _TicketRecord.fromMap(String id, Map<dynamic, dynamic> m) {
    final cls = _s(m['class']);
    final klass =
        cls == 'firstClass' ? TicketClass.firstClass : TicketClass.regular;

    // purchasedAt may be legacy millis OR new string
    String? purchasedStr;
    DateTime? purchasedParsed;
    final rawPurchased = m['purchasedAt'];
    if (rawPurchased is num) {
      try {
        purchasedParsed =
            DateTime.fromMillisecondsSinceEpoch(rawPurchased.toInt());
        purchasedStr =
            '${purchasedParsed.month}/${purchasedParsed.day}/${purchasedParsed.year}';
      } catch (_) {}
    } else if (rawPurchased is String) {
      purchasedStr = rawPurchased;
      purchasedParsed = _parseDate(rawPurchased);
    }

    final activatedStr =
        _s(m['activatedAt']).isEmpty ? null : _s(m['activatedAt']);
    final expiresStr = _s(m['expiresAt']).isEmpty ? null : _s(m['expiresAt']);

    return _TicketRecord(
      id: id,
      productId: _s(m['productId']),
      klass: klass,
      title: _s(m['title']),
      priceSar: _i(m['priceSar']),
      purchasedAtStr: purchasedStr,
      activatedAtStr: activatedStr,
      expiresAtStr: expiresStr,
      activated: _b(m['activated']),
      expired: _b(m['expired']),
      purchasedAt: purchasedParsed,
      activatedAt: _parseDate(activatedStr),
      expiresAt: _parseDate(expiresStr),
    );
  }
}

class PurchaseHistoryScreen extends StatelessWidget {
  const PurchaseHistoryScreen({super.key});

  DatabaseReference _refForUser(User? u) =>
      FirebaseDatabase.instance.ref('App/Tickets/${u?.uid ?? 'anon'}');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.kBackGroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.kBackGroundColor,
        elevation: 0,
        centerTitle: false,
        title: Text(
          getTranslated(context, 'Purchase History'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: _refForUser(FirebaseAuth.instance.currentUser).onValue,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(strokeWidth: 2));
          }

          final raw = snap.data?.snapshot.value;
          if (raw == null) return _empty(context, theme);

          Map<dynamic, dynamic> map;
          try {
            map = Map<dynamic, dynamic>.from(raw as Map);
          } catch (_) {
            return _empty(context, theme);
          }

          final list = <_TicketRecord>[];
          map.forEach((k, v) {
            if (v is Map) {
              final mv = Map<dynamic, dynamic>.from(v);
              if (mv.containsKey('productId') && mv.containsKey('class')) {
                list.add(_TicketRecord.fromMap(k.toString(), mv));
              }
            }
          });

          if (list.isEmpty) return _empty(context, theme);

          // sort newest first
          list.sort((a, b) {
            final da = a.purchasedAt;
            final db = b.purchasedAt;
            if (da == null && db != null) return 1;
            if (db == null && da != null) return -1;
            if (da == null && db == null) return a.title.compareTo(b.title);
            return db!.compareTo(da!);
          });

          // group by Month Year (localized month name)
          final groups = <String, List<_TicketRecord>>{};
          for (final r in list) {
            final d = r.purchasedAt ?? DateTime(1970, 1, 1);
            final key = '${_monthName(context, d.month)} ${d.year}';
            groups.putIfAbsent(key, () => []).add(r);
          }

          final groupKeys = groups.keys.toList();
          // Responsive: list on phones, grid on larger screens
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 700;
              return CustomScrollView(
                slivers: [
                  for (final gk in groupKeys) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          gk,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .2,
                          ),
                        ),
                      ),
                    ),
                    if (!wide)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList.separated(
                          itemCount: groups[gk]!.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) =>
                              _HistoryTile(record: groups[gk]![i]),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid.builder(
                          itemCount: groups[gk]!.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 16 / 7, // roomy, good for tablets
                          ),
                          itemBuilder: (_, i) =>
                              _HistoryTile(record: groups[gk]![i]),
                        ),
                      ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 18)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _empty(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.receipt_long_rounded,
                size: 56, color: Colors.black26),
            const SizedBox(height: 12),
            Text(
              getTranslated(context, 'No purchases yet'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              getTranslated(context,
                  'Your tickets will appear here once you purchase them.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  String _monthName(BuildContext context, int m) {
    switch (m) {
      case 1:
        return getTranslated(context, 'January');
      case 2:
        return getTranslated(context, 'February');
      case 3:
        return getTranslated(context, 'March');
      case 4:
        return getTranslated(context, 'April');
      case 5:
        return getTranslated(context, 'May');
      case 6:
        return getTranslated(context, 'June');
      case 7:
        return getTranslated(context, 'July');
      case 8:
        return getTranslated(context, 'August');
      case 9:
        return getTranslated(context, 'September');
      case 10:
        return getTranslated(context, 'October');
      case 11:
        return getTranslated(context, 'November');
      case 12:
        return getTranslated(context, 'December');
      default:
        return getTranslated(context, 'Unknown');
    }
  }
}

class _HistoryTile extends StatelessWidget {
  final _TicketRecord record;
  const _HistoryTile({required this.record});

  Color get _chipColor {
    if (record.expired) return const Color(0xFFB00020);
    if (record.activated) return const Color(0xFF2E7D32);
    return const Color(0xFF455A64);
  }

  String _fmt(DateTime d) => '${d.month}/${d.day}/${d.year}';
  String _fmtDt(DateTime d) =>
      '${d.month}/${d.day}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isFirst = record.klass == TicketClass.firstClass;
    final labelBg = isFirst ? const Color(0xFF8F7A4E) : const Color(0xFFE6E8DC);
    final labelFg = isFirst ? Colors.white : Colors.black87;

    // localized status text
    final String statusText = record.expired
        ? getTranslated(context, 'Expired')
        : (record.activated
            ? getTranslated(context, 'Activated')
            : getTranslated(context, 'Not activated'));

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetails(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              // Left accent
              Container(
                width: 6,
                height: 76,
                decoration: BoxDecoration(
                  color: isFirst
                      ? const Color(0xFFBFA574)
                      : AppColors.kPrimaryColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              // Main info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // top line: title + price
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            // LOCALIZED product title
                            getTranslated(context, record.title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Text(
                          '﷼ ${record.priceSar}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // purchased + class chip
                    Row(
                      children: [
                        Text(
                          '${getTranslated(context, 'Purchased on')} ${record.purchasedAtStr ?? (record.purchasedAt != null ? _fmt(record.purchasedAt!) : getTranslated(context, 'Unknown'))}',
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 12),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: labelBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            record.klass == TicketClass.firstClass
                                ? getTranslated(context, 'FIRST CLASS')
                                : getTranslated(context, 'REGULAR'),
                            style: TextStyle(
                                color: labelFg,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // status + dates (compact)
                    Row(
                      children: [
                        _StatusChip(text: statusText, color: _chipColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _secondaryLine(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.black54, fontSize: 12),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: Colors.black26),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _secondaryLine(BuildContext context) {
    if (record.activated &&
        record.activatedAt != null &&
        record.expiresAt != null) {
      return '${getTranslated(context, 'Activated at')} ${record.activatedAtStr} • ${getTranslated(context, 'Expires at')} ${record.expiresAtStr}';
    }
    if (record.activated && record.expiresAt != null) {
      return '${getTranslated(context, 'Expires at')} ${record.expiresAtStr}';
    }
    return getTranslated(context, 'Not yet activated');
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                // LOCALIZED product title
                getTranslated(context, record.title),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 10),
              _kv(context, getTranslated(context, 'Price'),
                  '﷼ ${record.priceSar}'),
              _kv(
                  context,
                  getTranslated(context, 'Class'),
                  record.klass == TicketClass.firstClass
                      ? getTranslated(context, 'First Class')
                      : getTranslated(context, 'Regular')),
              _kv(context, getTranslated(context, 'Purchased on'),
                  record.purchasedAtStr ?? '-'),
              _kv(context, getTranslated(context, 'Activated at'),
                  record.activatedAtStr ?? '-'),
              _kv(context, getTranslated(context, 'Expires at'),
                  record.expiresAtStr ?? '-'),
              _kv(
                  context,
                  getTranslated(context, 'Status'),
                  record.expired
                      ? getTranslated(context, 'Expired')
                      : (record.activated
                          ? getTranslated(context, 'Activated')
                          : getTranslated(context, 'Not activated'))),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(k, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: .2,
        ),
      ),
    );
  }
}
