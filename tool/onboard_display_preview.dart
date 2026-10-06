import 'package:darb/widgets/onboard_display.dart';
import 'package:flutter/material.dart';

void main() => runApp(const _OnboardPreviewApp());

class _OnboardPreviewApp extends StatelessWidget {
  const _OnboardPreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF42C879),
        useMaterial3: true,
      ),
      home: const _OnboardPreviewHome(),
    );
  }
}

class _OnboardPreviewHome extends StatelessWidget {
  const _OnboardPreviewHome();

  static const _lines = <({String key, Color color, String destination})>[
    (key: 'Blue', color: Color(0xFF1E88E5), destination: 'SAB Bank'),
    (
      key: 'Red',
      color: Color(0xFFE53935),
      destination: 'Ministry of Education'
    ),
    (
      key: 'Green',
      color: Color(0xFF43A047),
      destination: 'King Abdulaziz Road'
    ),
    (key: 'Yellow', color: Color(0xFFFBC02D), destination: 'Airport T5'),
    (key: 'Orange', color: Color(0xFFFB8C00), destination: 'Qasr Al Hokm'),
    (key: 'Purple', color: Color(0xFF8E24AA), destination: 'Grandia'),
  ];

  Future<void> _showLine(
    BuildContext context, {
    required String line,
    required Color color,
    required String destination,
  }) {
    final stops = <MetroStop>[
      const MetroStop(
        id: 'start',
        nameEn: 'Current station',
        nameAr: 'المحطة الحالية',
      ),
      const MetroStop(
        id: 'next',
        nameEn: 'Next station',
        nameAr: 'المحطة التالية',
      ),
      MetroStop(
        id: 'destination',
        nameEn: destination,
        nameAr: destination,
        isTransfer: true,
        transferLines: const ['Blue'],
      ),
    ];

    return showOnboardDisplay(
      context,
      stops: stops,
      currentIndex: 0,
      lineKey: line,
      lineColor: color,
      directionNameEn: 'To $destination',
      directionNameAr: 'إلى $destination',
      etaToNext: const Duration(minutes: 4),
      nextStationOverride: 'Next station',
      fullLineStops: stops,
      alightHere: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Onboard display previews')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Choose a metro line',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Each preview uses the production onboard display widget.',
              ),
              const SizedBox(height: 20),
              for (final line in _lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: line.color,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () => _showLine(
                      context,
                      line: line.key,
                      color: line.color,
                      destination: line.destination,
                    ),
                    icon: const Icon(Icons.directions_subway_rounded),
                    label: Text('${line.key} Line'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
