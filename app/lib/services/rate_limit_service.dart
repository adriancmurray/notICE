import 'package:shared_preferences/shared_preferences.dart';

/// Service for rate limiting report submissions.
/// 
/// Enforces 1 report per hour per device using local storage.
class RateLimitService {
  RateLimitService._();
  static final RateLimitService instance = RateLimitService._();

  static const _lastReportKey = 'last_report_timestamp';
  static const _cooldownDuration = Duration(hours: 1);

  SharedPreferences? _prefs;

  Future<void> _ensureInitialized() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Check if the user can submit a new report.
  /// 
  /// Returns true if cooldown has passed, false otherwise.
  Future<bool> canSubmitReport() async {
    await _ensureInitialized();
    
    final lastTimestamp = _prefs!.getInt(_lastReportKey);
    if (lastTimestamp == null) return true;
    
    final lastReport = DateTime.fromMillisecondsSinceEpoch(lastTimestamp);
    final elapsed = DateTime.now().difference(lastReport);
    
    return elapsed >= _cooldownDuration;
  }

  /// Get the remaining cooldown time.
  /// 
  /// Returns Duration.zero if no cooldown is active.
  Future<Duration> getRemainingCooldown() async {
    await _ensureInitialized();
    
    final lastTimestamp = _prefs!.getInt(_lastReportKey);
    if (lastTimestamp == null) return Duration.zero;
    
    final lastReport = DateTime.fromMillisecondsSinceEpoch(lastTimestamp);
    final elapsed = DateTime.now().difference(lastReport);
    
    if (elapsed >= _cooldownDuration) return Duration.zero;
    
    return _cooldownDuration - elapsed;
  }

  /// Record that a report was just submitted.
  Future<void> recordReportSubmission() async {
    await _ensureInitialized();
    await _prefs!.setInt(_lastReportKey, DateTime.now().millisecondsSinceEpoch);
  }
}
