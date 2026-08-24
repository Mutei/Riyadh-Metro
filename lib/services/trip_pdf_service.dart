import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

/// Builds the original clean, structured trip report from actual stored data.
class TripPdfService {
  TripPdfService._();

  static final instance = TripPdfService._();

  static const _brand = PdfColor.fromInt(0xFF16766D);
  static const _brandDark = PdfColor.fromInt(0xFF0D4E49);
  static const _ink = PdfColor.fromInt(0xFF182625);
  static const _muted = PdfColor.fromInt(0xFF647371);
  static const _panel = PdfColor.fromInt(0xFFF2F7F5);
  static const _border = PdfColor.fromInt(0xFFD9E6E2);

  Future<pw.Font>? _arabicFont;

  Future<File> generateTripReport(TripPdfReportData trip) async {
    final segments = await _loadSegments(trip.id);
    final file = await _reportFile(trip);
    await file.writeAsBytes(await _buildPdf(trip, segments), flush: true);
    return file;
  }

  Future<void> exportAndShare(TripPdfReportData trip) async {
    final file = await generateTripReport(trip);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: _TripPdfCopy.forLanguage(trip.languageCode).shareMessage,
    );
  }

  Future<File> _reportFile(TripPdfReportData trip) async {
    final root = await getApplicationDocumentsDirectory();
    final reports =
        Directory('${root.path}${Platform.pathSeparator}trip_reports');
    if (!await reports.exists()) await reports.create(recursive: true);

    final date = '${trip.startedAt.year.toString().padLeft(4, '0')}-'
        '${trip.startedAt.month.toString().padLeft(2, '0')}-'
        '${trip.startedAt.day.toString().padLeft(2, '0')}';
    return File('${reports.path}${Platform.pathSeparator}'
        'Trip_Report_${date}_${_filenamePart(trip.id)}.pdf');
  }

  Future<List<TripPdfSegment>> _loadSegments(String tripId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const [];

    dynamic raw;
    try {
      raw = (await FirebaseDatabase.instance
              .ref('App/TravelHistory/$uid/$tripId/metroSegments')
              .get())
          .value;
    } catch (_) {
      return const [];
    }
    if (raw is! Map) return const [];

    final segments = <TripPdfSegment>[];
    raw.forEach((key, value) {
      if (value is! Map) return;
      final data = Map<Object?, Object?>.from(value);
      segments.add(TripPdfSegment(
        id: key.toString(),
        fromStation: (data['fromStation'] ?? data['from'] ?? '').toString(),
        toStation: (data['toStation'] ?? data['to'] ?? '').toString(),
        lineKey: (data['lineKey'] ?? '').toString(),
        seconds: (data['seconds'] as num?)?.toInt() ?? 0,
        startedAt: _dateFrom(data['startedAt']),
        finishedAt: _dateFrom(data['finishedAt']),
      ));
    });
    segments.sort((a, b) {
      final aTime = a.startedAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.startedAt?.millisecondsSinceEpoch ?? 0;
      return aTime == bTime ? a.id.compareTo(b.id) : aTime.compareTo(bTime);
    });
    return segments;
  }

  DateTime? _dateFrom(dynamic value) =>
      value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;

  Future<List<int>> _buildPdf(
    TripPdfReportData trip,
    List<TripPdfSegment> segments,
  ) async {
    final copy = _TripPdfCopy.forLanguage(trip.languageCode);
    final isArabic = copy.arabic;
    final arabicFont = isArabic ? await _loadArabicFont() : null;
    final theme = pw.ThemeData.withFont(
      base: arabicFont ?? pw.Font.helvetica(),
      bold: arabicFont ?? pw.Font.helveticaBold(),
    );
    final document = pw.Document(theme: theme);

    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(34, 34, 34, 42),
          theme: theme,
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.center,
          child: _text(
            copy.pageLabel(context.pageNumber, context.pagesCount),
            isArabic: isArabic,
            style: const pw.TextStyle(color: _muted, fontSize: 8),
          ),
        ),
        build: (_) => [
          _hero(trip, copy, isArabic),
          pw.SizedBox(height: 22),
          _sectionTitle(copy.tripOverview, isArabic),
          pw.SizedBox(height: 10),
          _overview(trip, copy, isArabic),
          pw.SizedBox(height: 20),
          _sectionTitle(copy.routeDetails, isArabic),
          pw.SizedBox(height: 10),
          _routeDetails(trip, copy, isArabic),
          pw.SizedBox(height: 20),
          _sectionTitle(copy.tripTimeline, isArabic),
          pw.SizedBox(height: 10),
          if (segments.isEmpty)
            _emptyTimeline(copy, isArabic)
          else
            ...segments.asMap().entries.map(
                  (entry) => _timelineItem(
                    entry.value,
                    entry.key + 1,
                    copy,
                    isArabic,
                  ),
                ),
          pw.SizedBox(height: 18),
          _note(copy.generatedNote, isArabic),
        ],
      ),
    );
    return document.save();
  }

  Future<pw.Font> _loadArabicFont() => _arabicFont ??= () async {
        final bytes = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
        return pw.Font.ttf(bytes);
      }();

  pw.Widget _hero(TripPdfReportData trip, _TripPdfCopy copy, bool isArabic) =>
      pw.Container(
        padding: const pw.EdgeInsets.all(22),
        decoration: pw.BoxDecoration(
          gradient: const pw.LinearGradient(
            colors: [_brand, _brandDark],
            begin: pw.Alignment.topLeft,
            end: pw.Alignment.bottomRight,
          ),
          borderRadius: pw.BorderRadius.circular(18),
        ),
        child: pw
            .Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('DARB',
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 17,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 2)),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromInt(0x28FFFFFF),
                    borderRadius: pw.BorderRadius.circular(999),
                  ),
                  child: _text(copy.completedStatus(trip.finishedAt != null),
                      isArabic: isArabic,
                      style: const pw.TextStyle(
                          color: PdfColors.white, fontSize: 9)),
                ),
              ]),
          pw.SizedBox(height: 22),
          _text(copy.tripReport,
              isArabic: isArabic,
              style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 25,
                  fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 7),
          _text('${copy.tripDate}: ${_formatDate(trip.startedAt, isArabic)}',
              isArabic: isArabic,
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
          pw.SizedBox(height: 16),
          pw.Wrap(spacing: 8, runSpacing: 8, children: [
            _heroPill('${copy.reference}: ${trip.id}'),
            _heroPill('${copy.mode}: ${copy.modeLabel(trip.mode)}'),
          ]),
        ]),
      );

  pw.Widget _heroPill(String value) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(0x24FFFFFF),
          borderRadius: pw.BorderRadius.circular(999),
        ),
        child: pw.Text(value,
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 8.5)),
      );

  pw.Widget _overview(
          TripPdfReportData trip, _TripPdfCopy copy, bool isArabic) =>
      pw.Row(children: [
        pw.Expanded(
            child: _metricCard(copy.startTime,
                _formatTime(trip.startedAt, isArabic), isArabic)),
        pw.SizedBox(width: 9),
        pw.Expanded(
            child: _metricCard(
                copy.endTime,
                trip.finishedAt == null
                    ? copy.notFinished
                    : _formatTime(trip.finishedAt!, isArabic),
                isArabic)),
        pw.SizedBox(width: 9),
        pw.Expanded(
            child: _metricCard(
                copy.duration,
                _formatDuration(trip.durationSeconds, copy, isArabic),
                isArabic)),
        pw.SizedBox(width: 9),
        pw.Expanded(
            child: _metricCard(
                copy.distance,
                _formatDistance(trip.distanceMeters, copy, isArabic),
                isArabic)),
      ]);

  pw.Widget _metricCard(String label, String value, bool isArabic) =>
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: _panel,
          borderRadius: pw.BorderRadius.circular(10),
          border: pw.Border.all(color: _border),
        ),
        child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _text(label,
                  isArabic: isArabic,
                  style: const pw.TextStyle(color: _muted, fontSize: 8)),
              pw.SizedBox(height: 5),
              _text(value,
                  isArabic: isArabic,
                  style: pw.TextStyle(
                      color: _ink,
                      fontSize: 10.5,
                      fontWeight: pw.FontWeight.bold)),
            ]),
      );

  pw.Widget _routeDetails(
      TripPdfReportData trip, _TripPdfCopy copy, bool isArabic) {
    final lineNames = trip.metroLineKeys.isEmpty
        ? copy.notAvailable
        : trip.metroLineKeys.join(isArabic ? '، ' : ', ');
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child:
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        _routeStop(copy.origin, _orUnknown(trip.originLabel, copy), isArabic,
            isStart: true),
        pw.Container(
            width: 1.2,
            height: 18,
            margin: const pw.EdgeInsets.only(left: 7),
            color: _border),
        _routeStop(
            copy.destination, _orUnknown(trip.destinationLabel, copy), isArabic,
            isStart: false),
        if (trip.mode == 'metro') ...[
          pw.SizedBox(height: 16),
          _detailRow(copy.metroLines, lineNames, isArabic),
          _detailRow(
              copy.fromStation, _orUnknown(trip.fromStation, copy), isArabic),
          _detailRow(
              copy.toStation, _orUnknown(trip.toStation, copy), isArabic),
        ],
      ]),
    );
  }

  pw.Widget _routeStop(String label, String value, bool isArabic,
          {required bool isStart}) =>
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(
          width: 15,
          height: 15,
          margin: const pw.EdgeInsets.only(top: 1),
          decoration: pw.BoxDecoration(
            color: isStart ? _brand : PdfColor.fromInt(0xFFD95D4F),
            shape: pw.BoxShape.circle,
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
              _text(label,
                  isArabic: isArabic,
                  style: const pw.TextStyle(color: _muted, fontSize: 8)),
              pw.SizedBox(height: 2),
              _text(value,
                  isArabic: isArabic,
                  style: pw.TextStyle(
                      color: _ink,
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold)),
            ])),
      ]);

  pw.Widget _detailRow(String label, String value, bool isArabic) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child:
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(
              width: 105,
              child: _text(label,
                  isArabic: isArabic,
                  style: const pw.TextStyle(color: _muted, fontSize: 9))),
          pw.Expanded(
              child: _text(value,
                  isArabic: isArabic,
                  style: const pw.TextStyle(color: _ink, fontSize: 9.5))),
        ]),
      );

  pw.Widget _timelineItem(TripPdfSegment segment, int index, _TripPdfCopy copy,
          bool isArabic) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child:
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(
            width: 23,
            height: 23,
            alignment: pw.Alignment.center,
            decoration:
                pw.BoxDecoration(color: _brand, shape: pw.BoxShape.circle),
            child: pw.Text('$index',
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 9)),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
              child: pw.Container(
            padding: const pw.EdgeInsets.all(11),
            decoration: pw.BoxDecoration(
                color: _panel, borderRadius: pw.BorderRadius.circular(10)),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _text(
                      '${_orUnknown(segment.fromStation, copy)} ${copy.to} ${_orUnknown(segment.toStation, copy)}',
                      isArabic: isArabic,
                      style: pw.TextStyle(
                          color: _ink,
                          fontSize: 10.5,
                          fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  _text(_segmentMeta(segment, copy, isArabic),
                      isArabic: isArabic,
                      style: const pw.TextStyle(color: _muted, fontSize: 8.5)),
                ]),
          )),
        ]),
      );

  pw.Widget _emptyTimeline(_TripPdfCopy copy, bool isArabic) => pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
            color: _panel, borderRadius: pw.BorderRadius.circular(10)),
        child: _text(copy.noSegmentData,
            isArabic: isArabic,
            style: const pw.TextStyle(color: _muted, fontSize: 9.5)),
      );

  pw.Widget _note(String note, bool isArabic) => pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFF8FAF9),
            borderRadius: pw.BorderRadius.circular(8)),
        child: _text(note,
            isArabic: isArabic,
            style: const pw.TextStyle(color: _muted, fontSize: 8)),
      );

  pw.Widget _sectionTitle(String title, bool isArabic) => _text(title,
      isArabic: isArabic,
      style: pw.TextStyle(
          color: _ink, fontSize: 14, fontWeight: pw.FontWeight.bold));

  pw.Widget _text(String value,
          {required bool isArabic, pw.TextStyle? style}) =>
      pw.Directionality(
        textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        child: pw.Text(value,
            style: style,
            textAlign: isArabic ? pw.TextAlign.right : pw.TextAlign.left),
      );

  String _segmentMeta(
      TripPdfSegment segment, _TripPdfCopy copy, bool isArabic) {
    final details = <String>[];
    if (segment.lineKey.trim().isNotEmpty)
      details.add('${copy.line}: ${segment.lineKey}');
    if (segment.seconds > 0)
      details.add(_formatDuration(segment.seconds, copy, isArabic));
    if (segment.startedAt != null)
      details.add(_formatTime(segment.startedAt!, isArabic));
    return details.isEmpty ? copy.noAdditionalDetails : details.join(' | ');
  }

  String _formatDate(DateTime date, bool isArabic) {
    final value = isArabic
        ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return _localizeDigits(value, isArabic);
  }

  String _formatTime(DateTime date, bool isArabic) => _localizeDigits(
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
      isArabic);

  String _formatDuration(int seconds, _TripPdfCopy copy, bool isArabic) {
    final minutes = (seconds / 60).round();
    final value = minutes < 60
        ? '$minutes ${copy.minutes}'
        : '${minutes ~/ 60} ${copy.hours}${minutes % 60 == 0 ? '' : ' ${minutes % 60} ${copy.minutes}'}';
    return _localizeDigits(value, isArabic);
  }

  String _formatDistance(int meters, _TripPdfCopy copy, bool isArabic) =>
      _localizeDigits(
          meters < 1000
              ? '$meters ${copy.meters}'
              : '${(meters / 1000).toStringAsFixed(1)} ${copy.kilometers}',
          isArabic);

  String _localizeDigits(String value, bool isArabic) {
    if (!isArabic) return value;
    const western = '0123456789';
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    return value.split('').map((char) {
      final index = western.indexOf(char);
      return index < 0 ? char : eastern[index];
    }).join();
  }

  String _orUnknown(String? value, _TripPdfCopy copy) =>
      value == null || value.trim().isEmpty ? copy.unknown : value.trim();

  String _filenamePart(String id) {
    final safe = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    if (safe.isEmpty) return DateTime.now().millisecondsSinceEpoch.toString();
    return safe.substring(0, safe.length > 12 ? 12 : safe.length);
  }
}

class TripPdfReportData {
  final String id;
  final String mode;
  final String originLabel;
  final String destinationLabel;
  final int durationSeconds;
  final int distanceMeters;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final List<String> metroLineKeys;
  final String? fromStation;
  final String? toStation;
  final String languageCode;

  const TripPdfReportData({
    required this.id,
    required this.mode,
    required this.originLabel,
    required this.destinationLabel,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.startedAt,
    required this.finishedAt,
    required this.metroLineKeys,
    required this.fromStation,
    required this.toStation,
    required this.languageCode,
  });
}

class TripPdfSegment {
  final String id;
  final String fromStation;
  final String toStation;
  final String lineKey;
  final int seconds;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  const TripPdfSegment({
    required this.id,
    required this.fromStation,
    required this.toStation,
    required this.lineKey,
    required this.seconds,
    required this.startedAt,
    required this.finishedAt,
  });
}

class _TripPdfCopy {
  final bool arabic;
  const _TripPdfCopy._(this.arabic);

  factory _TripPdfCopy.forLanguage(String languageCode) =>
      _TripPdfCopy._(languageCode.toLowerCase().startsWith('ar'));

  String get tripReport => arabic ? 'تقرير الرحلة' : 'Trip Report';
  String get tripDate => arabic ? 'تاريخ الرحلة' : 'Trip date';
  String get reference => arabic ? 'المرجع' : 'Reference';
  String get mode => arabic ? 'الوسيلة' : 'Mode';
  String get tripOverview => arabic ? 'ملخص الرحلة' : 'Trip overview';
  String get routeDetails => arabic ? 'تفاصيل المسار' : 'Route details';
  String get tripTimeline => arabic ? 'التسلسل الزمني للرحلة' : 'Trip timeline';
  String get startTime => arabic ? 'وقت البدء' : 'Start time';
  String get endTime => arabic ? 'وقت الانتهاء' : 'End time';
  String get duration => arabic ? 'المدة' : 'Duration';
  String get distance => arabic ? 'المسافة' : 'Distance';
  String get origin => arabic ? 'نقطة الانطلاق' : 'Origin';
  String get destination => arabic ? 'الوجهة' : 'Destination';
  String get metroLines => arabic ? 'خطوط المترو' : 'Metro lines';
  String get fromStation => arabic ? 'محطة الانطلاق' : 'From station';
  String get toStation => arabic ? 'محطة الوصول' : 'To station';
  String get notAvailable => arabic ? 'غير متاح' : 'Not available';
  String get unknown => arabic ? 'غير معروف' : 'Unknown';
  String get notFinished => arabic ? 'لم تنتهِ' : 'Not finished';
  String get noSegmentData => arabic
      ? 'لا توجد بيانات تفصيلية للمقاطع مسجلة لهذه الرحلة.'
      : 'No detailed segment data was recorded for this trip.';
  String get noAdditionalDetails =>
      arabic ? 'لا توجد تفاصيل إضافية' : 'No additional details';
  String get generatedNote => arabic
      ? 'تم إنشاء هذا التقرير من بيانات الرحلة المسجلة في درب.'
      : 'This report was generated from the trip information recorded in Darb.';
  String get shareMessage =>
      arabic ? 'تقرير رحلة من درب' : 'Trip report from Darb';
  String get minutes => arabic ? 'دقيقة' : 'min';
  String get hours => arabic ? 'ساعة' : 'hr';
  String get meters => arabic ? 'م' : 'm';
  String get kilometers => arabic ? 'كم' : 'km';
  String get to => arabic ? 'إلى' : 'to';
  String get line => arabic ? 'الخط' : 'Line';

  String modeLabel(String value) => value == 'metro'
      ? (arabic ? 'المترو' : 'Metro')
      : (arabic ? 'سيارة' : 'Car');

  String completedStatus(bool complete) => complete
      ? (arabic ? 'مكتملة' : 'Completed')
      : (arabic ? 'قيد التنفيذ' : 'In progress');

  String pageLabel(int page, int total) =>
      arabic ? 'صفحة $page من $total' : 'Page $page of $total';
}
