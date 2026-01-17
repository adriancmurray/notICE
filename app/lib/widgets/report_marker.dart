import 'package:flutter/material.dart';
import 'package:app/models/report.dart';

/// Marker widget for a report on the map.
class ReportMarker extends StatelessWidget {
  final Report report;
  final VoidCallback? onTap;

  const ReportMarker({
    super.key,
    required this.report,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Color(report.type.colorValue),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Color(report.type.colorValue).withValues(alpha: 0.5),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Text(
            report.type.emoji,
            style: const TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}
