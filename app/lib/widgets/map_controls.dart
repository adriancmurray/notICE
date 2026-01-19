import 'dart:ui';
import 'package:flutter/material.dart';

class MapControls extends StatelessWidget {
  final VoidCallback onCenterLocation;
  final VoidCallback onReport;
  final bool canReport; // True when GPS available

  const MapControls({
    super.key,
    required this.onCenterLocation,
    required this.onReport,
    this.canReport = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Location Button (Glass)
        _GlassButton(
          onTap: onCenterLocation,
          child: const Icon(Icons.my_location, color: Colors.white),
        ),
        const SizedBox(height: 16),
        
        // Report Button (Large Glass + Gradient)
        GestureDetector(
          onTap: canReport ? onReport : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  gradient: canReport
                    ? LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                          Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                  color: canReport ? null : Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: canReport 
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.red.withValues(alpha: 0.5),
                    width: 1,
                  ),
                  boxShadow: canReport ? [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ] : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      canReport ? Icons.add_alert : Icons.gps_off,
                      color: canReport ? Colors.black : Colors.red.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      canReport ? 'REPORT' : 'NO GPS',
                      style: TextStyle(
                        color: canReport ? Colors.black : Colors.red.withValues(alpha: 0.7),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const _GlassButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color?.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
