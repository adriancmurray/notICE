import 'package:flutter/material.dart';
import 'package:app/controllers/map_controller.dart';

/// Horizontal chip bar for time range filtering.
class TimeFilterBar extends StatelessWidget {
  final TimeFilter selected;
  final ValueChanged<TimeFilter> onChanged;

  const TimeFilterBar({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: TimeFilter.values.map((filter) {
          final isSelected = selected == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(filter.label),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) onChanged(filter);
              },
              selectedColor: Theme.of(context).colorScheme.primaryContainer,
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              labelStyle: TextStyle(
                fontSize: 12,
                color: isSelected 
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
