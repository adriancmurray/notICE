import 'package:flutter/material.dart';
import 'package:app/models/report.dart';
import 'package:app/services/pocketbase_service.dart';
import 'package:app/services/vote_tracking_service.dart';

/// Bottom sheet displaying report details with vote buttons.
class ReportDetailSheet extends StatefulWidget {
  final Report report;
  final VoidCallback? onVoted;

  const ReportDetailSheet({
    super.key,
    required this.report,
    this.onVoted,
  });

  @override
  State<ReportDetailSheet> createState() => _ReportDetailSheetState();
}

class _ReportDetailSheetState extends State<ReportDetailSheet> {
  final _pocketbaseService = PocketbaseService.instance;
  bool _isVoting = false;
  String? _voteStatus; // 'confirm', 'dispute', or null

  @override
  void initState() {
    super.initState();
    _loadVoteStatus();
  }

  Future<void> _loadVoteStatus() async {
    final status = await VoteTrackingService.instance.getVoteStatus(widget.report.id);
    if (mounted) {
      setState(() => _voteStatus = status);
    }
  }

  Future<void> _confirmReport() async {
    if (_voteStatus != null || _isVoting) return;
    
    setState(() => _isVoting = true);
    try {
      await _pocketbaseService.confirmReport(widget.report.id);
      setState(() => _voteStatus = 'confirm');
      widget.onVoted?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report confirmed ✅'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isVoting = false);
    }
  }

  Future<void> _disputeReport() async {
    if (_voteStatus != null || _isVoting) return;
    
    setState(() => _isVoting = true);
    try {
      await _pocketbaseService.disputeReport(widget.report.id);
      setState(() => _voteStatus = 'dispute');
      widget.onVoted?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report disputed ❌'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isVoting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasVoted = _voteStatus != null;
    final report = widget.report;
    
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with emoji and type
          Row(
            children: [
              Text(report.type.emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.type.displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      report.timeAgo,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Credibility badge
              _CredibilityBadge(report: report),
            ],
          ),
          
          // Description
          if (report.description?.isNotEmpty ?? false) ...[
            const SizedBox(height: 16),
            Text(report.description!, style: const TextStyle(fontSize: 16)),
          ],
          
          const SizedBox(height: 20),
          
          // Vote status or buttons
          if (hasVoted)
            _VotedIndicator(voteStatus: _voteStatus!)
          else
            _VoteButtons(
              isVoting: _isVoting,
              onConfirm: _confirmReport,
              onDispute: _disputeReport,
            ),
          
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}

class _CredibilityBadge extends StatelessWidget {
  final Report report;
  
  const _CredibilityBadge({required this.report});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: report.isDisputed 
          ? Colors.red.withValues(alpha: 0.2)
          : Colors.green.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('✅ ${report.confirmations}', style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          Text('❌ ${report.disputes}', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _VotedIndicator extends StatelessWidget {
  final String voteStatus;
  
  const _VotedIndicator({required this.voteStatus});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        voteStatus == 'confirm' 
          ? 'You confirmed this report ✅'
          : 'You disputed this report ❌',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _VoteButtons extends StatelessWidget {
  final bool isVoting;
  final VoidCallback onConfirm;
  final VoidCallback onDispute;

  const _VoteButtons({
    required this.isVoting,
    required this.onConfirm,
    required this.onDispute,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isVoting ? null : onConfirm,
            icon: const Text('✅'),
            label: const Text('Confirm'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green,
              side: const BorderSide(color: Colors.green),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isVoting ? null : onDispute,
            icon: const Text('❌'),
            label: const Text('Dispute'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}
