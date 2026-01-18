/// Configuration for the notICE app.
/// 
/// In production, these values should come from environment variables
/// or a build-time configuration system.
import 'package:flutter/foundation.dart' show kIsWeb;

class AppConfig {
  AppConfig._();

  /// PocketBase server URL.
  /// 
  /// When served from PocketBase on web, uses same origin (empty string).
  /// Otherwise uses environment variable or default.
  static String get pocketbaseUrl {
    // On web, if POCKETBASE_URL is empty, use same origin (/)
    if (kIsWeb) {
      const envUrl = String.fromEnvironment('POCKETBASE_URL', defaultValue: '');
      return envUrl.isEmpty ? '' : envUrl;
    }
    // On native platforms, require explicit URL
    return const String.fromEnvironment(
      'POCKETBASE_URL',
      defaultValue: 'https://epic-area-industry-clerk.trycloudflare.com',
    );
  }

  /// Geohash precision for spatial indexing.
  /// 
  /// Precision 6 = ~1.2km x 0.6km cells
  /// Precision 7 = ~150m x 150m cells
  static const int geohashPrecision = 6;

  /// Default map center (fallback if location unavailable).
  /// 
  /// Currently set to Denver, CO as placeholder.
  static const double defaultLat = 39.7392;
  static const double defaultLong = -104.9903;

  /// Default map zoom level.
  static const double defaultZoom = 14.0;

  /// OpenStreetMap tile server URL.
  /// 
  /// Using the standard OSM tile server. For production, consider
  /// hosting your own tile server or using a privacy-respecting
  /// provider like Stadia Maps.
  static const String osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// User agent for tile requests (required by OSM usage policy).
  static const String userAgent = 'notICE/1.0 (https://github.com/adriancmurray/notICE)';
}
