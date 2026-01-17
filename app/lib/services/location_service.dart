import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:app/config/app_config.dart';

/// Service for device location access.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  StreamSubscription<Position>? _positionSubscription;
  final _locationController = StreamController<LatLng>.broadcast();

  /// Stream of location updates.
  Stream<LatLng> get locationStream => _locationController.stream;

  /// Last known location.
  LatLng? _lastLocation;
  LatLng? get lastLocation => _lastLocation;

  /// Default location (used when permissions denied).
  LatLng get defaultLocation => const LatLng(
    AppConfig.defaultLat,
    AppConfig.defaultLong,
  );

  /// Check and request location permissions.
  Future<bool> checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Get the current location.
  Future<LatLng> getCurrentLocation() async {
    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      return defaultLocation;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      _lastLocation = LatLng(position.latitude, position.longitude);
      return _lastLocation!;
    } catch (e) {
      return _lastLocation ?? defaultLocation;
    }
  }

  /// Start listening to location updates.
  Future<void> startTracking({
    int distanceFilter = 50, // meters
  }) async {
    final hasPermission = await checkPermissions();
    if (!hasPermission) return;

    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
      ),
    ).listen((position) {
      _lastLocation = LatLng(position.latitude, position.longitude);
      _locationController.add(_lastLocation!);
    });
  }

  /// Stop location tracking.
  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Dispose resources.
  void dispose() {
    stopTracking();
    _locationController.close();
  }
}
