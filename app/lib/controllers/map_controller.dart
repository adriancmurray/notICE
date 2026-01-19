import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:app/models/report.dart';
import 'package:app/services/geohash_service.dart';
import 'package:app/services/location_service.dart';
import 'package:app/services/pocketbase_service.dart';
import 'package:app/services/push_notification_service.dart';

/// Time filter options for report display.
enum TimeFilter {
  oneHour(1, '1h'),
  sixHours(6, '6h'),
  day(24, '24h'),
  threeDays(72, '3d'),
  week(168, '7d'),
  all(-1, 'All');

  const TimeFilter(this.hours, this.label);
  final int hours;
  final String label;
}

/// Controller for the map screen.
/// 
/// Manages report data, location tracking, subscriptions, and push state.
/// Separates business logic from UI rendering.
class MapController extends ChangeNotifier {
  MapController._();
  static final MapController instance = MapController._();

  // Services
  final _pocketbaseService = PocketbaseService.instance;
  final _locationService = LocationService.instance;
  final _geohashService = GeohashService.instance;
  final _pushService = PushNotificationService.instance;

  // State
  final List<Report> _reports = [];
  LatLng? _currentLocation;
  TimeFilter _timeFilter = TimeFilter.day;
  bool _isLoading = false;
  String? _error;
  
  // Subscriptions
  StreamSubscription<Report>? _reportSubscription;
  StreamSubscription<LatLng>? _locationSubscription;

  // Getters
  List<Report> get reports => List.unmodifiable(_reports);
  
  /// Returns reports that should be visible (not heavily disputed).
  List<Report> get visibleReports => 
      _reports.where((r) => !r.isDisputed).toList();
  
  LatLng? get currentLocation => _currentLocation;
  TimeFilter get timeFilter => _timeFilter;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get pushSupported => _pushService.isSupported;
  bool _pushEnabled = false;
  bool get pushEnabled => _pushEnabled;
  String get currentGeohash => _currentLocation != null
      ? _geohashService.encode(_currentLocation!.latitude, _currentLocation!.longitude)
      : '';

  /// Initialize the controller.
  /// 
  /// Call this once during widget initialization.
  Future<void> initialize() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Initialize services
      await _pocketbaseService.initialize();
      await _pushService.initialize();
      _pushEnabled = await _pushService.isEnabled();

      // Get initial location
      await _initLocation();

      // Fetch initial reports
      await refreshReports();

      // Subscribe to realtime updates
      await _subscribeToReports();

      // Listen for location changes
      _locationSubscription = _locationService.locationStream.listen(_onLocationUpdate);
    } catch (e) {
      _error = 'Failed to initialize: $e';
      debugPrint('MapController init error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _initLocation() async {
    try {
      _currentLocation = await _locationService.getCurrentLocation();
      await _locationService.startTracking();
    } catch (e) {
      // Use default location if permission denied
      _currentLocation = _locationService.defaultLocation;
      debugPrint('Location unavailable, using default: $e');
    }
  }

  void _onLocationUpdate(LatLng location) {
    _currentLocation = location;
    notifyListeners();
    // Could re-subscribe to new geohashes here if significant movement
  }

  Future<void> _subscribeToReports() async {
    if (_currentLocation == null) return;

    final geohash = _geohashService.encode(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
    );
    
    final geohashes = _geohashService.getNeighborhood(geohash);

    await _pocketbaseService.subscribeToGeohashes(geohashes);
    
    // Listen for new reports
    _reportSubscription?.cancel();
    _reportSubscription = _pocketbaseService.reportsStream.listen(_onNewReport);
  }

  void _onNewReport(Report report) {
    // Add to list if not duplicate
    final exists = _reports.any((r) => r.id == report.id);
    if (!exists) {
      _reports.insert(0, report);
      notifyListeners();
    }
  }

  /// Refresh reports with current time filter.
  Future<void> refreshReports() async {
    if (_currentLocation == null) return;

    final geohash = _geohashService.encode(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
    );

    final geohashes = _geohashService.getNeighborhood(geohash);
    final sinceHours = _timeFilter.hours > 0 ? _timeFilter.hours : 8760; // 1 year for "All"

    try {
      final reports = await _pocketbaseService.fetchReports(
        geohashes: geohashes,
        sinceHours: sinceHours,
      );
      
      _reports.clear();
      _reports.addAll(reports);
      _error = null;
    } catch (e) {
      _error = 'Failed to load reports: $e';
      debugPrint('Refresh reports error: $e');
    }
    
    notifyListeners();
  }

  /// Set the time filter and refresh reports.
  void setTimeFilter(TimeFilter filter) {
    if (_timeFilter == filter) return;
    _timeFilter = filter;
    notifyListeners();
    refreshReports();
  }

  /// Toggle push notifications.
  /// 
  /// Returns null on success, or an error message on failure.
  Future<String?> togglePush() async {
    if (!pushSupported) {
      return 'Push notifications not supported';
    }

    if (pushEnabled) {
      await _pushService.disableNotifications();
      _pushEnabled = false;
      notifyListeners();
      return null;
    }

    if (currentGeohash.isEmpty) {
      return 'Location required for notifications';
    }

    final result = await _pushService.enableNotifications(currentGeohash);
    if (result == null) {
      _pushEnabled = true;
    }
    notifyListeners();
    return result;
  }

  /// Confirm a report.
  Future<void> confirmReport(String reportId) async {
    await _pocketbaseService.confirmReport(reportId);
    await refreshReports();
  }

  /// Dispute a report.
  Future<void> disputeReport(String reportId) async {
    await _pocketbaseService.disputeReport(reportId);
    await refreshReports();
  }

  /// Dispose resources.
  @override
  void dispose() {
    _reportSubscription?.cancel();
    _locationSubscription?.cancel();
    _pocketbaseService.dispose();
    _locationService.dispose();
    super.dispose();
  }
}
