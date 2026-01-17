import 'package:dart_geohash/dart_geohash.dart';
import 'package:latlong2/latlong.dart';
import 'package:app/config/app_config.dart';

/// Service for geohash calculations and neighbor lookups.
class GeohashService {
  GeohashService._();
  static final GeohashService instance = GeohashService._();

  final _geoHasher = GeoHasher();

  /// Encode a lat/long pair to a geohash string.
  String encode(double lat, double long, {int? precision}) {
    return _geoHasher.encode(
      long, // Note: dart_geohash uses (long, lat) order
      lat,
      precision: precision ?? AppConfig.geohashPrecision,
    );
  }

  /// Encode a LatLng object to a geohash string.
  String encodeLatLng(LatLng location, {int? precision}) {
    return encode(location.latitude, location.longitude, precision: precision);
  }

  /// Decode a geohash to its center point.
  LatLng decode(String geohash) {
    final decoded = _geoHasher.decode(geohash);
    return LatLng(decoded[1], decoded[0]); // Convert (long, lat) to LatLng
  }

  /// Get all 8 neighboring geohashes plus the center hash.
  /// 
  /// Returns a set of 9 geohashes that cover the area around
  /// the given location.
  Set<String> getNeighborhood(String centerHash) {
    final neighbors = _geoHasher.neighbors(centerHash);
    return {
      centerHash,
      neighbors['n']!,
      neighbors['ne']!,
      neighbors['e']!,
      neighbors['se']!,
      neighbors['s']!,
      neighbors['sw']!,
      neighbors['w']!,
      neighbors['nw']!,
    };
  }

  /// Get neighborhood geohashes for a lat/long location.
  Set<String> getNeighborhoodForLocation(double lat, double long) {
    final centerHash = encode(lat, long);
    return getNeighborhood(centerHash);
  }

  /// Build a PocketBase filter string for a set of geohashes.
  /// 
  /// Returns a filter like: (geohash ~ "abc123" || geohash ~ "abc124" || ...)
  String buildGeohashFilter(Set<String> geohashes) {
    final conditions = geohashes.map((h) => 'geohash ~ "$h"').join(' || ');
    return '($conditions)';
  }
}
