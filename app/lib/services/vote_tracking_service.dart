import 'package:shared_preferences/shared_preferences.dart';

/// Service for tracking votes on reports.
/// 
/// Prevents gaming by ensuring each device can only vote once per report.
class VoteTrackingService {
  VoteTrackingService._();
  static final VoteTrackingService instance = VoteTrackingService._();

  static const _confirmPrefix = 'vote_confirm_';
  static const _disputePrefix = 'vote_dispute_';

  SharedPreferences? _prefs;

  Future<void> _ensureInitialized() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Check if the user has already confirmed this report.
  Future<bool> hasConfirmed(String reportId) async {
    await _ensureInitialized();
    return _prefs!.getBool('$_confirmPrefix$reportId') ?? false;
  }

  /// Check if the user has already disputed this report.
  Future<bool> hasDisputed(String reportId) async {
    await _ensureInitialized();
    return _prefs!.getBool('$_disputePrefix$reportId') ?? false;
  }

  /// Check if the user has voted on this report (either confirm or dispute).
  Future<bool> hasVoted(String reportId) async {
    final confirmed = await hasConfirmed(reportId);
    final disputed = await hasDisputed(reportId);
    return confirmed || disputed;
  }

  /// Record that the user confirmed this report.
  Future<void> recordConfirmation(String reportId) async {
    await _ensureInitialized();
    await _prefs!.setBool('$_confirmPrefix$reportId', true);
  }

  /// Record that the user disputed this report.
  Future<void> recordDispute(String reportId) async {
    await _ensureInitialized();
    await _prefs!.setBool('$_disputePrefix$reportId', true);
  }

  /// Get the user's vote status for a report.
  /// Returns 'confirm', 'dispute', or null if not voted.
  Future<String?> getVoteStatus(String reportId) async {
    if (await hasConfirmed(reportId)) return 'confirm';
    if (await hasDisputed(reportId)) return 'dispute';
    return null;
  }
}
