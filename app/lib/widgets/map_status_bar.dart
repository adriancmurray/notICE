import 'dart:ui';
import 'package:flutter/material.dart';

class MapStatusBar extends StatelessWidget {
  final int reportCount;
  final String? telegramLink;
  final bool pushSupported;
  final bool pushEnabled;
  final VoidCallback onTogglePush;
  final VoidCallback? onTestPush;
  final int selectedTimeFilter;
  final ValueChanged<int> onTimeFilterChanged;

  const MapStatusBar({
    super.key,
    required this.reportCount,
    this.telegramLink,
    required this.pushSupported,
    required this.pushEnabled,
    required this.onTogglePush,
    this.onTestPush,
    required this.selectedTimeFilter,
    required this.onTimeFilterChanged,
  });

  static const _timeFilterOptions = {
    1: '1h',
    6: '6h',
    24: '24h',
    72: '3d',
    168: '7d',
    0: 'All',
  };

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color?.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Row: Logo, Stats, Actions
              Row(
                children: [
                  const Text('🧊', style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'notICE',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          '$reportCount reports nearby',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Live Indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 8, color: Colors.green),
                        SizedBox(width: 4),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Second Row: Actions & Filters
              Row(
                children: [
                  if (pushSupported) ...[
                    // Push Toggle
                    InkWell(
                      onTap: onTogglePush,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: pushEnabled 
                            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: pushEnabled 
                              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                              : Colors.transparent,
                          ),
                        ),
                        child: Icon(
                          pushEnabled ? Icons.notifications_active : Icons.notifications_off,
                          size: 20,
                          color: pushEnabled 
                            ? Theme.of(context).colorScheme.primary 
                            : Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  
                  // Time Filters
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _timeFilterOptions.entries.map((entry) {
                          final isSelected = selectedTimeFilter == entry.key;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => onTimeFilterChanged(entry.key),
                                borderRadius: BorderRadius.circular(20),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12, 
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected 
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.white.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: Text(
                                    entry.value,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected ? Colors.black : Colors.white70,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
