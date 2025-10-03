// lib/screens/ticket_screen.dart
import 'dart:ui' show FontFeature; // for tabular figures in remaining time

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../constants/colors.dart';
import '../widgets/bottom_navigation_bar.dart';
import '../localization/language_constants.dart';

enum TicketClass { regular, firstClass }

class TicketProduct {
  final String id;
  final TicketClass klass;
  final String title; // kept English; translated on render
  final String description; // kept English; translated on render
  final int priceSar;

  const TicketProduct({
    required this.id,
    required this.klass,
    required this.title,
    required this.description,
    required this.priceSar,
  });
}

class TicketRecord {
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

  TicketRecord({
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
        final day = int.tryParse(d[1]);
        final y = int.tryParse(d[2]);
        int hh = 0, mm = 0;
        if (parts.length > 1) {
          final t = parts[1].split(':');
          if (t.length >= 2) {
            hh = int.tryParse(t[0]) ?? 0;
            mm = int.tryParse(t[1]) ?? 0;
          }
        }
        if (m != null && day != null && y != null) {
          return DateTime(y, m, day, hh, mm);
        }
      }
    } catch (_) {}
    return null;
  }

  factory TicketRecord.fromMap(String id, Map<dynamic, dynamic> m) {
    final cls = _s(m['class']);
    final klass =
        cls == 'firstClass' ? TicketClass.firstClass : TicketClass.regular;

    // purchasedAt can be legacy millis OR new string
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
    final activatedAt = _parseDate(activatedStr);
    final expiresAt = _parseDate(expiresStr);

    return TicketRecord(
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
      activatedAt: activatedAt,
      expiresAt: expiresAt,
    );
  }
}

class TicketScreen extends StatefulWidget {
  const TicketScreen({super.key});

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  int _tabIndex = 1;

  final Set<String> _selected = {};
  final Set<String> _expanded = {};

  late final DatabaseReference _userTicketsRef;
  late final String? _uid;

  // Keep English literals; translate them when rendering.
  final List<TicketProduct> _regular = const [
    TicketProduct(
      id: 'reg_2h',
      klass: TicketClass.regular,
      title: '2 hours pass',
      description: 'Unlimited rides for two hours after activation.',
      priceSar: 4,
    ),
    TicketProduct(
      id: 'reg_3d',
      klass: TicketClass.regular,
      title: '3 days pass',
      description: 'Unlimited rides for 3 days after activation.',
      priceSar: 20,
    ),
    TicketProduct(
      id: 'reg_7d',
      klass: TicketClass.regular,
      title: '7 days pass',
      description: 'Unlimited rides for 7 days after activation.',
      priceSar: 40,
    ),
    TicketProduct(
      id: 'reg_30d',
      klass: TicketClass.regular,
      title: '30 days pass',
      description: 'Unlimited rides for 30 days after activation.',
      priceSar: 140,
    ),
  ];

  final List<TicketProduct> _first = const [
    TicketProduct(
      id: 'fc_2h',
      klass: TicketClass.firstClass,
      title: 'First Class 2-hour Pass',
      description: 'First class metro + bus for two hours after activation.',
      priceSar: 10,
    ),
    TicketProduct(
      id: 'fc_3d',
      klass: TicketClass.firstClass,
      title: 'First Class 3-day Pass',
      description: 'First class metro + bus for 3 days after activation.',
      priceSar: 50,
    ),
    TicketProduct(
      id: 'fc_7d',
      klass: TicketClass.firstClass,
      title: 'First Class 7-day Pass',
      description: 'First class metro + bus for 7 days after activation.',
      priceSar: 100,
    ),
    TicketProduct(
      id: 'fc_30d',
      klass: TicketClass.firstClass,
      title: 'First Class 30-day Pass',
      description: 'First class metro + bus for 30 days after activation.',
      priceSar: 350,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _userTicketsRef =
        FirebaseDatabase.instance.ref('App/Tickets/${_uid ?? 'anon'}');
  }

  // --- date helpers ---
  String _fmtDate(DateTime d) => '${d.month}/${d.day}/${d.year}';
  String _fmtDateTime(DateTime d) =>
      '${d.month}/${d.day}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Duration _durationForProduct(String id) {
    switch (id) {
      case 'reg_2h':
      case 'fc_2h':
        return const Duration(hours: 2);
      case 'reg_3d':
      case 'fc_3d':
        return const Duration(days: 3);
      case 'reg_7d':
      case 'fc_7d':
        return const Duration(days: 7);
      case 'reg_30d':
      case 'fc_30d':
        return const Duration(days: 30);
      default:
        return const Duration(days: 1);
    }
  }

  bool _isCurrentlyActive(TicketRecord r) {
    if (!r.activated || r.expired) return false;
    if (r.expiresAt == null) return true;
    return DateTime.now().isBefore(r.expiresAt!);
  }

  /// New: Check if the user already has an active (not yet expired) ticket.
  Future<bool> _hasActiveTicket() async {
    try {
      final snap = await _userTicketsRef.get();
      final raw = snap.value;
      if (raw is! Map) return false;

      for (final entry in raw.entries) {
        final k = entry.key;
        final v = entry.value;
        if (v is Map) {
          final mv = Map<dynamic, dynamic>.from(v);
          if (mv.containsKey('productId') && mv.containsKey('class')) {
            final rec = TicketRecord.fromMap(k.toString(), mv);
            if (_isCurrentlyActive(rec)) {
              return true;
            }
          }
        }
      }
      return false;
    } catch (_) {
      // On error, fail open (allow buy) to avoid blocking due to transient issues.
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.kBackGroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.kBackGroundColor,
        elevation: 0,
        centerTitle: false,
        title: Text(
          getTranslated(context, 'Tickets'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _PillTabs(
              leftLabel: getTranslated(context, 'My Tickets'),
              rightLabel: getTranslated(context, 'Buy Ticket'),
              index: _tabIndex,
              onChanged: (i) => setState(() => _tabIndex = i),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: (_tabIndex == 0) ? _myTicketsTab() : _buyList(),
          ),
        ],
      ),
      bottomNavigationBar: BottomNav(
        index: 2,
        onChanged: (i) async {
          if (i == 2) return;
          if (!mounted) return;
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/mainScreen', (r) => false);
        },
      ),
    );
  }

  // ================= BUY TAB =================

  Widget _buyList() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      children: [
        ..._regular.map((p) => _ticketCard(p)),
        const SizedBox(height: 6),
        ..._first.map((p) => _ticketCard(p)),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _ticketCard(TicketProduct p) {
    final isFirst = p.klass == TicketClass.firstClass;

    final Color cardBg = isFirst ? const Color(0xFFBFA574) : Colors.white;
    final Color border = isFirst ? Colors.transparent : Colors.black12;
    final Color labelBg =
        isFirst ? const Color(0xFF8F7A4E) : const Color(0xFFE6E8DC);
    final Color labelFg = isFirst ? Colors.white : Colors.black87;

    final bool selected = _selected.contains(p.id);
    final bool expanded = _expanded.contains(p.id);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: labelBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isFirst
                      ? getTranslated(context, 'FIRST CLASS')
                      : getTranslated(context, 'REGULAR CLASS'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: .5,
                    fontWeight: FontWeight.w700,
                    color: labelFg,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 28,
                height: 28,
                child: Checkbox(
                  value: selected,
                  onChanged: (_) async {
                    // optimistic toggle for UI
                    setState(() {
                      if (selected) {
                        _selected.remove(p.id);
                      } else {
                        _selected.add(p.id);
                      }
                    });
                    if (!selected) {
                      // When user tries to buy, enforce "only one active ticket".
                      final hasActive = await _hasActiveTicket();
                      if (hasActive) {
                        _notify(getTranslated(context,
                            'You already have an active ticket. You can buy a new one after it expires.'));
                        if (mounted) {
                          setState(() => _selected.remove(p.id));
                        }
                        return;
                      }
                      await _confirmAndBuy(p);
                    }
                  },
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                  side: BorderSide(
                      color: Colors.black.withOpacity(.5), width: 1.6),
                  activeColor: AppColors.kPrimaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            getTranslated(context, p.title),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isFirst ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '﷼ ${p.priceSar}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: isFirst ? Colors.white : AppColors.kPrimaryColor,
                  height: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            getTranslated(context, p.description),
            softWrap: true,
            style: TextStyle(
              color: isFirst ? Colors.white.withOpacity(.9) : Colors.black87,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              setState(() {
                if (expanded) {
                  _expanded.remove(p.id);
                } else {
                  _expanded.add(p.id);
                }
              });
            },
            child: Row(
              children: [
                Text(
                  getTranslated(context, 'See details'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isFirst ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 22,
                  color: isFirst ? Colors.white : Colors.black,
                ),
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 8),
            Divider(color: isFirst ? Colors.white54 : Colors.black12),
            const SizedBox(height: 8),
            Text(
              '${getTranslated(context, '• Unlimited rides within the validity period')}\n'
              '${getTranslated(context, '• Activate from your “My Tickets” tab')}\n'
              '${getTranslated(context, '• Non-refundable after activation')}',
              softWrap: true,
              style: const TextStyle(height: 1.3),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmAndBuy(TicketProduct p) async {
    if (_uid == null) {
      _notify(getTranslated(context, 'Please log in to buy tickets.'));
      return;
    }

    // Safety check again right before finalizing purchase
    if (await _hasActiveTicket()) {
      _notify(getTranslated(context,
          'You already have an active ticket. You can buy a new one after it expires.'));
      return;
    }

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getTranslated(context, 'Buy ticket?')),
        content: Text(
          '${getTranslated(context, 'Purchase')} “${getTranslated(context, p.title)}” '
          '${getTranslated(context, 'for')} ﷼ ${p.priceSar}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(getTranslated(context, 'Cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(getTranslated(context, 'Buy')),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final now = DateTime.now();
      final newRef = _userTicketsRef.push();
      await newRef.set({
        'productId': p.id,
        'class': p.klass == TicketClass.firstClass ? 'firstClass' : 'regular',
        'title': getTranslated(context, p.title),
        'priceSar': p.priceSar,
        'purchasedAt': _fmtDate(now), // "M/d/yyyy"
        'activated': false,
        'activatedAt': null,
        'expiresAt': null,
        'expired': false,
      });
      _notify(getTranslated(context, 'Ticket added to My Tickets.'));
      setState(() => _tabIndex = 0);
    } catch (e) {
      _notify('${getTranslated(context, 'Could not complete purchase:')} $e');
    }
  }

  // ================= MY TICKETS TAB =================

  Widget _myTicketsTab() {
    return StreamBuilder<DatabaseEvent>(
      stream: _userTicketsRef.onValue,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        final raw = snap.data?.snapshot.value;
        if (raw == null) return _myTicketsPlaceholder();

        Map<dynamic, dynamic> map;
        try {
          map = Map<dynamic, dynamic>.from(raw as Map);
        } catch (_) {
          return _myTicketsPlaceholder();
        }

        final records = <TicketRecord>[];
        map.forEach((k, v) {
          try {
            if (v is Map) {
              final mv = Map<dynamic, dynamic>.from(v);
              if (mv.containsKey('productId') && mv.containsKey('class')) {
                records.add(TicketRecord.fromMap(k.toString(), mv));
              }
            }
          } catch (_) {}
        });

        if (records.isEmpty) return _myTicketsPlaceholder();

        // mark expired (idempotent)
        final now = DateTime.now();
        for (final r in records) {
          if (r.activated &&
              r.expiresAt != null &&
              now.isAfter(r.expiresAt!) &&
              !r.expired) {
            _userTicketsRef
                .child(r.id)
                .update({'expired': true}).catchError((_) {});
          }
        }

        final visible = records.where((r) => !r.expired).toList();
        if (visible.isEmpty) return _myTicketsPlaceholder();

        visible.sort((a, b) {
          final da = a.purchasedAt;
          final db = b.purchasedAt;
          if (da == null && db != null) return 1;
          if (db == null && da != null) return -1;
          if (da == null && db == null) return a.title.compareTo(b.title);
          return db!.compareTo(da!);
        });

        final children = <Widget>[];
        for (var i = 0; i < visible.length; i++) {
          final r = visible[i];
          children.add(_buildTicketItem(r));
          if (i != visible.length - 1) children.add(const SizedBox(height: 12));
        }

        // NO slivers; also no InkWell splash => no RenderTransform
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );
      },
    );
  }

  Widget _buildTicketItem(TicketRecord r) {
    try {
      final product = _productFromId(r.productId);
      if (product == null) return _unknownTicketCard(r);
      return _myTicketCard(product, r);
    } catch (e) {
      return _errorRow(
          '${getTranslated(context, 'Could not render ticket:')} $e');
    }
  }

  Widget _myTicketsPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.confirmation_number_outlined,
                size: 56, color: Colors.black26),
            const SizedBox(height: 12),
            Text(
              getTranslated(context, 'No active tickets'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              getTranslated(
                  context, 'When you purchase a ticket it will appear here.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unknownTicketCard(TicketRecord r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.report_problem_rounded, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${getTranslated(context, 'Unknown ticket (product:)')} ${r.productId}',
              softWrap: true,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorRow(String msg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD6D6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg,
                softWrap: true, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _myTicketCard(TicketProduct p, TicketRecord r) {
    final isFirst = p.klass == TicketClass.firstClass;
    final cardBg = isFirst ? const Color(0xFFBFA574) : Colors.white;
    final border = isFirst ? Colors.transparent : Colors.black12;
    final labelBg = isFirst ? const Color(0xFF8F7A4E) : const Color(0xFFE6E8DC);
    final labelFg = isFirst ? Colors.white : Colors.black87;

    final purchasedStr = r.purchasedAtStr ?? getTranslated(context, 'Unknown');
    final bool activeNow = _isCurrentlyActive(r);

    // Use GestureDetector (no Ink splash/transform)
    return GestureDetector(
      onTap: () async {
        if (!r.activated) {
          await _promptActivate(r, p);
        } else if (activeNow) {
          _showQrLarge(r, p);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: labelBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isFirst
                        ? getTranslated(context, 'FIRST CLASS')
                        : getTranslated(context, 'REGULAR CLASS'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: .5,
                      fontWeight: FontWeight.w700,
                      color: labelFg,
                    ),
                  ),
                ),
                const Spacer(),
                if (r.activated && activeNow)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      getTranslated(context, 'Activated'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                if (r.activated && !activeNow)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      getTranslated(context, 'Expired'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              getTranslated(context, p.title),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isFirst ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${getTranslated(context, 'Purchased on')} $purchasedStr',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isFirst ? Colors.white70 : Colors.black54,
                fontSize: 12,
              ),
            ),
            if (r.activated) ...[
              const SizedBox(height: 6),
              Text(
                '${getTranslated(context, 'Activated:')} ${r.activatedAtStr ?? '—'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isFirst ? Colors.white70 : Colors.black54,
                  fontSize: 12,
                ),
              ),
              Text(
                '${getTranslated(context, 'Expires:')} ${r.expiresAtStr ?? '—'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isFirst ? Colors.white70 : Colors.black54,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 10),

            // Action row: Activate / QR
            Row(
              children: [
                if (!r.activated)
                  ElevatedButton.icon(
                    onPressed: () => _promptActivate(r, p),
                    icon: const Icon(Icons.play_circle_fill_rounded),
                    label: Text(getTranslated(context, 'Activate')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.kPrimaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                if (activeNow)
                  ElevatedButton.icon(
                    onPressed: () => _showQrLarge(r, p),
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: Text(getTranslated(context, 'Show QR')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isFirst ? Colors.black.withOpacity(.2) : Colors.black,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
              ],
            ),

            // Inline compact QR preview for quick scan (tap expands)
            if (activeNow) ...[
              const SizedBox(height: 12),
              _inlineQrStrip(r, p, isFirst),
            ],
          ],
        ),
      ),
    );
  }

  Widget _inlineQrStrip(TicketRecord r, TicketProduct p, bool isFirst) {
    final payload = _qrPayload(r, p);
    final remainStr = _remainingText(r);
    return GestureDetector(
      onTap: () => _showQrLarge(r, p),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:
              isFirst ? Colors.white.withOpacity(.15) : const Color(0xFFF6F7F3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isFirst ? Colors.white30 : Colors.black12),
        ),
        child: Row(
          children: [
            // Small QR
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 64,
                gapless: true,
              ),
            ),
            const SizedBox(width: 12),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(getTranslated(context, 'Metro entry QR'),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: isFirst ? Colors.white : Colors.black87,
                      )),
                  const SizedBox(height: 2),
                  Text(
                    getTranslated(context, 'Tap to enlarge for gate scan'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isFirst ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  if (remainStr != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${getTranslated(context, 'Time remaining:')} $remainStr',
                      style: TextStyle(
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: isFirst ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.open_in_full_rounded, size: 20),
          ],
        ),
      ),
    );
  }

  String? _remainingText(TicketRecord r) {
    if (r.expiresAt == null) return null;
    final now = DateTime.now();
    final diff = r.expiresAt!.difference(now);
    if (diff.isNegative) return getTranslated(context, 'Expired');
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    if (h > 0) {
      return '${h}${getTranslated(context, 'h')} ${m}${getTranslated(context, 'm')}';
    }
    return '${m}${getTranslated(context, 'm')}';
  }

  void _showQrLarge(TicketRecord r, TicketProduct p) {
    final payload = _qrPayload(r, p);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(getTranslated(context, 'Scan at metro gate'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 260,
                gapless: true,
              ),
              const SizedBox(height: 8),
              Text(
                getTranslated(context, p.title),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                r.expiresAtStr != null
                    ? '${getTranslated(context, 'Expires:')} ${r.expiresAtStr}'
                    : '',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 6),
              const Divider(height: 1),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.brightness_high_rounded, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      getTranslated(context,
                          'Increase screen brightness for faster scanning.'),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(getTranslated(context, 'Close')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Encodes all info the gate needs to validate.
  /// Example JSON string; keep short for fast scans.
  String _qrPayload(TicketRecord r, TicketProduct p) {
    // Keep payload compact; parsers can expect these keys.
    // If you add server-side signature later, include "sig".
    final uid = _uid ?? 'anon';
    final klass = p.klass == TicketClass.firstClass ? 'FC' : 'RG';
    final act = r.activatedAt?.toIso8601String() ?? '';
    final exp = r.expiresAt?.toIso8601String() ?? '';
    return '{"t":"metroPass","uid":"$uid","rid":"${r.id}","pid":"${p.id}","k":"$klass","act":"$act","exp":"$exp"}';
  }

  Future<void> _promptActivate(TicketRecord r, TicketProduct p) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getTranslated(context, 'Activate ticket?')),
        content: Text(getTranslated(context,
            'Are you sure you want to activate your ticket? Activation starts the validity period.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(getTranslated(context, 'Cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(getTranslated(context, 'Activate')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _activateTicket(r.id, p);
    }
  }

  Future<void> _activateTicket(String recordId, TicketProduct p) async {
    try {
      final now = DateTime.now();
      final expires = now.add(_durationForProduct(p.id));
      await _userTicketsRef.child(recordId).update({
        'activated': true,
        'activatedAt': _fmtDateTime(now), // "M/d/yyyy HH:mm"
        'expiresAt': _fmtDateTime(expires), // "M/d/yyyy HH:mm"
        'expired': false,
      });
      _notify(getTranslated(context, 'Ticket activated.'));
    } catch (e) {
      _notify('${getTranslated(context, 'Activation failed:')} $e');
    }
  }

  TicketProduct? _productFromId(String id) {
    for (final p in _regular) {
      if (p.id == id) return p;
    }
    for (final p in _first) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _notify(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ======= Pill tabs =======

class _PillTabs extends StatelessWidget {
  final int index; // 0 = left, 1 = right
  final String leftLabel;
  final String rightLabel;
  final ValueChanged<int> onChanged;

  const _PillTabs({
    required this.index,
    required this.leftLabel,
    required this.rightLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bg = const Color(0xFFEAF0E4); // soft grey-green
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          _pill(
            context,
            label: leftLabel,
            selected: index == 0,
            onTap: () => onChanged(0),
          ),
          _pill(
            context,
            label: rightLabel,
            selected: index == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }

  Widget _pill(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: selected ? AppColors.kPrimaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.kPrimaryColor.withOpacity(.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
