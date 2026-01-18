import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:app/models/report.dart';
import 'package:app/services/rate_limit_service.dart';

/// Form for submitting a new report.
class ReportForm extends StatefulWidget {
  final LatLng location;
  final Future<void> Function(ReportType type, String? description) onSubmit;

  const ReportForm({
    super.key,
    required this.location,
    required this.onSubmit,
  });

  @override
  State<ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<ReportForm> {
  final _rateLimitService = RateLimitService.instance;
  ReportType _selectedType = ReportType.warning;
  final _descriptionController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _checkRateLimit();
  }

  Future<void> _checkRateLimit() async {
    // Pre-check rate limit status (could show UI warning in future)
    await _rateLimitService.getRemainingCooldown();
  }

  Future<void> _submit() async {
    // Check rate limit
    final canSubmit = await _rateLimitService.canSubmitReport();
    if (!canSubmit) {
      final remaining = await _rateLimitService.getRemainingCooldown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please wait ${remaining.inMinutes} minutes before submitting another report'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() => _isSubmitting = true);

    await widget.onSubmit(
      _selectedType,
      _descriptionController.text.isEmpty ? null : _descriptionController.text,
    );

    // Record submission time
    await _rateLimitService.recordReportSubmission();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Title
          const Text(
            'Report an Incident',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your location will be shared anonymously',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Type selector
          Row(
            children: ReportType.values.map((type) {
              final isSelected = type == _selectedType;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _TypeButton(
                    type: type,
                    isSelected: isSelected,
                    onTap: () => setState(() => _selectedType = type),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Description field
          TextField(
            controller: _descriptionController,
            maxLength: 200,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'What\'s happening? (optional)',
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              counterStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Submit button
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(_selectedType.colorValue),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _selectedType.emoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Submit ${_selectedType.displayName}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  final ReportType type;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeButton({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? Color(type.colorValue).withValues(alpha: 0.2)
              : Colors.black26,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Color(type.colorValue) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Text(
              type.emoji,
              style: const TextStyle(fontSize: 28),
            ),
            const SizedBox(height: 4),
            Text(
              type.displayName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? Color(type.colorValue)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
