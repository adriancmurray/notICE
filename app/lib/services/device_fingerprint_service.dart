import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Service for generating a persistent device fingerprint.
/// 
/// Creates a UUID on first run and stores it in SharedPreferences.
/// Used for server-side rate limiting without user accounts.
class DeviceFingerprintService {
  DeviceFingerprintService._();
  static final DeviceFingerprintService instance = DeviceFingerprintService._();

  static const _key = 'device_fingerprint';
  String? _fingerprint;

  /// Get or create the device fingerprint.
  Future<String> getFingerprint() async {
    if (_fingerprint != null) return _fingerprint!;
    
    final prefs = await SharedPreferences.getInstance();
    _fingerprint = prefs.getString(_key);
    
    if (_fingerprint == null) {
      _fingerprint = const Uuid().v4();
      await prefs.setString(_key, _fingerprint!);
    }
    
    return _fingerprint!;
  }
}
