// --- UI piece: station dropdown used in segment picker ---
import 'dart:ui';
import 'package:flutter/material.dart';

class StationDropdown extends StatelessWidget {
  final String label;
  final Color color;
  final List<Map<String, dynamic>> stations; // display-ordered list
  final int index; // selected index in the display-ordered list
  final ValueChanged<int> onChanged;

  const StationDropdown({
    required this.label,
    required this.color,
    required this.stations,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: index,
          isExpanded: true,
          items: List.generate(
            stations.length,
            (i) => DropdownMenuItem<int>(
              value: i,
              child: Text(stations[i]['name'] as String),
            ),
          ),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
