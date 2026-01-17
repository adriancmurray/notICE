/// Configuration for the notICE app.
/// 
/// In production, these values should come from environment variables
/// or a build-time configuration system.
class AppConfig {
  AppConfig._();

  /// PocketBase server URL.
  /// 
  /// For local development: 'http://127.0.0.1:8090'
  /// For production: 'https://notice.yourcity.gov'
  static const String pocketbaseUrl = String.fromEnvironment(
    'POCKETBASE_URL',
    defaultValue: 'http://127.0.0.1:8090',
  );

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
