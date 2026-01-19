import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:app/config/app_config.dart';
import 'package:app/models/report.dart';
import 'package:app/services/location_service.dart';
import 'package:app/services/pocketbase_service.dart';
import 'package:app/services/geohash_service.dart';
import 'package:app/services/vote_tracking_service.dart';
import 'package:app/services/push_notification_service.dart';
import 'package:app/widgets/report_marker.dart';
import 'package:app/widgets/report_form.dart';
import 'package:app/widgets/map_status_bar.dart';
import 'package:app/widgets/map_controls.dart';

/// Main map screen with realtime report updates.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  final _locationService = LocationService.instance;
  final _pocketbaseService = PocketbaseService.instance;
  final _geohashService = GeohashService.instance;

  // Start with Idaho Falls coordinates - will update when location/server responds
  LatLng _currentLocation = const LatLng(43.4926, -112.0401);
  LatLng _viewCenter = const LatLng(43.4926, -112.0401); // Track what user is looking at
  Set<String> _subscribedGeohashes = {};
  final List<Report> _reports = [];
  StreamSubscription? _reportsSubscription;
  Timer? _debounceTimer;
  
  // Time filter state
  int _selectedTimeFilter = 24; // Default to 24 hours
  String? _telegramLink; // Optional Telegram channel link from server
  StreamSubscription? _locationSubscription;
  bool _pushEnabled = false;
  bool _pushSupported = false;
  bool _hasAccurateLocation = false; // True only when GPS is available

  @override
  void initState() {
    super.initState();
    _initializeAsync();
  }

  Future<void> _initializeAsync() async {
    // Initialize PocketBase (non-blocking)
    try {
      await _pocketbaseService.initialize();
    } catch (e) {
      debugPrint('PocketBase init error: $e');
    }

    try {
      // Get location - GPS only, no fallback
      final loc = await _locationService.getCurrentLocation();
      if (mounted) {
        setState(() {
          _currentLocation = loc;
          _viewCenter = loc;
          _hasAccurateLocation = true; // GPS succeeded
        });
      }
    } catch (e) {
      debugPrint('Location service error: $e');
      // No fallback - reporting disabled without GPS
      if (mounted) {
        setState(() => _hasAccurateLocation = false);
      }
    }

    // Fetch Telegram link (if configured)
    try {
      final link = await _pocketbaseService.fetchTelegramLink();
      if (link != null && mounted) {
        setState(() => _telegramLink = link);
      }
    } catch (e) {
      debugPrint('Failed to fetch Telegram link: $e');
    }

    // Subscribe to location updates
    _locationSubscription = _locationService.locationStream.listen(_onLocationUpdate);
    
    try {
      await _locationService.startTracking();
    } catch (e) {
      debugPrint('Failed to start location tracking: $e');
    }

    // Subscribe to reports in current area
    try {
      await _updateSubscriptions();
    } catch (e) {
      debugPrint('Failed to update subscriptions: $e');
    }

    // Listen for new reports
    _reportsSubscription = _pocketbaseService.reportsStream.listen(_onNewReport);

    // Initialize push notifications
    try {
      await PushNotificationService.instance.initialize();
      final supported = PushNotificationService.instance.isSupported;
      final enabled = await PushNotificationService.instance.isEnabled();
      if (mounted) {
        setState(() {
          _pushSupported = supported;
          _pushEnabled = enabled;
        });
      }
    } catch (e) {
      debugPrint('Push notification init error: $e');
    }
  }

  Future<void> _updateSubscriptions() async {
    // Use _viewCenter (Map Center) instead of _currentLocation (GPS)
    // This allows users to browse reports by dragging the map
    final newGeohashes = _geohashService.getNeighborhoodForLocation(
      _viewCenter.latitude,
      _viewCenter.longitude,
    );

    // Only update if geohashes changed
    if (newGeohashes.difference(_subscribedGeohashes).isNotEmpty ||
        _subscribedGeohashes.difference(newGeohashes).isNotEmpty) {
      _subscribedGeohashes = newGeohashes;

      // Fetch existing reports with time filter
      final reports = await _pocketbaseService.fetchReports(
        geohashes: _subscribedGeohashes,
        sinceHours: _selectedTimeFilter == 0 ? 8760 : _selectedTimeFilter, // 0 = all (1 year)
      );

      setState(() {
        _reports.clear();
        _reports.addAll(reports);
      });

      // Subscribe to realtime updates
      await _pocketbaseService.subscribeToGeohashes(_subscribedGeohashes);
    }
  }

  void _onLocationUpdate(LatLng location) {
    // Only update marker, do NOT force map move or re-fetch
    // This adheres to "Decoupled View" principle
    setState(() => _currentLocation = location);
    
    // If we haven't initialized view center yet, do it once
    if (_viewCenter.latitude == 43.4926 && _viewCenter.longitude == -112.0401) {
       _viewCenter = location;
       _updateSubscriptions();
    }
  }

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    _viewCenter = camera.center;
    
    // Debounce updates to prevent thrashing network on every frame
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _updateSubscriptions();
    });
  }

  void _onNewReport(Report report) {
    setState(() {
      // Add to beginning of list (newest first)
      _reports.insert(0, report);
    });

    // Show brief notification
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Text(report.type.emoji),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'New ${report.type.displayName.toLowerCase()} report nearby',
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _centerOnLocation() {
    _mapController.move(_currentLocation, AppConfig.defaultZoom);
    // Sync view center to user location immediately
    _viewCenter = _currentLocation;
    _updateSubscriptions();
  }

  /// Refresh reports with current time filter
  Future<void> _refreshReports() async {
    if (_subscribedGeohashes.isEmpty) return;
    
    final reports = await _pocketbaseService.fetchReports(
      geohashes: _subscribedGeohashes,
      sinceHours: _selectedTimeFilter == 0 ? 8760 : _selectedTimeFilter,
    );
    
    if (mounted) {
      setState(() {
        _reports.clear();
        _reports.addAll(reports);
      });
    }
  }

  void _showReportForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReportForm(
        location: _viewCenter, // Use view center for reports? No, probably still user location for submission, or visual center if dragging pin. ReportForm usually takes user loc.
        // Actually, let's keep it as _currentLocation for submission accuracy, BUT many apps allow dropping pin at center. 
        // For now, let's assume Report is WHERE I AM. 
        onSubmit: _submitReport,
      ),
    );
  }

  Future<void> _togglePushNotifications() async {
    final pushService = PushNotificationService.instance;
    
    if (_pushEnabled) {
      // Disable
      final success = await pushService.disableNotifications();
      if (success && mounted) {
        setState(() => _pushEnabled = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Push notifications disabled'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      // Enable with current geohash
      // TODO: Should this be View Center or User Location?
      // User likely wants alerts for WHERE THEY ARE, not where they are looking.
      // So keeping _currentLocation for Push Subscriptions is correct.
      final geohash = _geohashService.encode(
        _currentLocation.latitude,
        _currentLocation.longitude,
      );
      final error = await pushService.enableNotifications(geohash);
      if (mounted) {
        if (error == null) {
          setState(() => _pushEnabled = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🔔 Push alerts enabled for this area!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          // Revert to simple message but keep error in debug console
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not enable notifications. Please allow notifications and try again.'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
  }

  Future<void> _submitReport(ReportType type, String? description) async {
    try {
      final report = await _pocketbaseService.submitReport(
        lat: _currentLocation.latitude,
        long: _currentLocation.longitude,
        type: type,
        description: description,
      );

      setState(() => _reports.insert(0, report));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // Parse error for user-friendly message
        String message = 'Failed to submit report';
        final errorStr = e.toString();
        
        if (errorStr.contains('wait 1 hour')) {
          message = 'Please wait 1 hour between reports';
        } else if (errorStr.contains('validation')) {
          message = 'Invalid report data. Please try again.';
        } else if (errorStr.contains('network') || errorStr.contains('connection')) {
          message = 'Network error. Check your connection.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _reportsSubscription?.cancel();
    _locationSubscription?.cancel();
    _debounceTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: AppConfig.defaultZoom,
              minZoom: 10,
              maxZoom: 18,
              onPositionChanged: _onMapPositionChanged,
            ),
            children: [
              // OSM Tile Layer
              TileLayer(
                urlTemplate: AppConfig.osmTileUrl,
                userAgentPackageName: 'dev.notice.app',
                tileBuilder: _darkTileBuilder,
              ),

              // Current location marker
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentLocation,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

              // Report markers (hide disputed reports with 2+ disputes)
              MarkerLayer(
                markers: _reports
                    .where((r) => !r.isDisputed) // Auto-hide disputed reports
                    .map((report) => Marker(
                      point: LatLng(report.lat, report.long),
                      width: 40,
                      height: 40,
                      child: ReportMarker(
                        report: report,
                        onTap: () => _showReportDetails(report),
                      ),
                    )).toList(),
              ),
            ],
          ),

          // Status bar - shows subscribed area
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: MapStatusBar(
              reportCount: _reports.length,
              telegramLink: _telegramLink,
              pushSupported: _pushSupported,
              pushEnabled: _pushEnabled,
              onTogglePush: _togglePushNotifications,
              onTestPush: _pushEnabled 
                  ? () => PushNotificationService.instance.testLocalNotification()
                  : null,
              selectedTimeFilter: _selectedTimeFilter,
              onTimeFilterChanged: (hours) {
                setState(() => _selectedTimeFilter = hours);
                _refreshReports();
              },
            ),
          ),

          // Location & Report Controls
          Positioned(
            bottom: 32,
            right: 16,
            child: MapControls(
              onCenterLocation: _centerOnLocation,
              onReport: _showReportForm,
              canReport: _hasAccurateLocation,
            ),
          ),
        ],
      ),

    );
  }

  /// Apply dark mode filter to tiles.
  Widget _darkTileBuilder(BuildContext context, Widget tileWidget, TileImage tile) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        -0.8, 0, 0, 0, 220,
        0, -0.8, 0, 0, 220,
        0, 0, -0.8, 0, 220,
        0, 0, 0, 1, 0,
      ]),
      child: tileWidget,
    );
  }

  void _showReportDetails(Report report) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ReportDetailSheet(
        report: report,
        pocketbaseService: _pocketbaseService,
        onVoted: () {
          // Refresh reports after voting
          _refreshReports();
        },
      ),
    );
  }
}

/// Bottom sheet showing report details with vote buttons.
class _ReportDetailSheet extends StatefulWidget {
  final Report report;
  final PocketbaseService pocketbaseService;
  final VoidCallback onVoted;

  const _ReportDetailSheet({
    required this.report,
    required this.pocketbaseService,
    required this.onVoted,
  });

  @override
  State<_ReportDetailSheet> createState() => _ReportDetailSheetState();
}

class _ReportDetailSheetState extends State<_ReportDetailSheet> {
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
      await widget.pocketbaseService.confirmReport(widget.report.id);
      setState(() => _voteStatus = 'confirm');
      widget.onVoted();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report confirmed ✅'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), behavior: SnackBarBehavior.floating),
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
      await widget.pocketbaseService.disputeReport(widget.report.id);
      setState(() => _voteStatus = 'dispute');
      widget.onVoted();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report disputed ❌'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), behavior: SnackBarBehavior.floating),
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
              Text(
                report.type.emoji,
                style: const TextStyle(fontSize: 32),
              ),
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
              Container(
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
                    Text(
                      '✅ ${report.confirmations}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '❌ ${report.disputes}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // Description
          if (report.description?.isNotEmpty ?? false) ...[
            const SizedBox(height: 16),
            Text(
              report.description!,
              style: const TextStyle(fontSize: 16),
            ),
          ],
          
          const SizedBox(height: 20),
          
          // Vote buttons
          if (hasVoted)
            Center(
              child: Text(
                _voteStatus == 'confirm' 
                  ? 'You confirmed this report ✅'
                  : 'You disputed this report ❌',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isVoting ? null : _confirmReport,
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
                    onPressed: _isVoting ? null : _disputeReport,
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
            ),
          
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}
