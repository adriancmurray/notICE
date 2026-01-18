import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app/config/app_config.dart';
import 'package:app/models/report.dart';
import 'package:app/services/location_service.dart';
import 'package:app/services/pocketbase_service.dart';
import 'package:app/services/geohash_service.dart';
import 'package:app/services/vote_tracking_service.dart';
import 'package:app/services/push_notification_service.dart';
import 'package:app/widgets/report_marker.dart';
import 'package:app/widgets/report_form.dart';

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
  Set<String> _subscribedGeohashes = {};
  final List<Report> _reports = [];
  StreamSubscription? _reportsSubscription;
  
  // Time filter options (in hours)
  static const _timeFilterOptions = {
    1: '1h',
    6: '6h',
    24: '24h',
    72: '3d',
    168: '7d',
    0: 'All',
  };
  int _selectedTimeFilter = 24; // Default to 24 hours
  String? _telegramLink; // Optional Telegram channel link from server
  StreamSubscription? _locationSubscription;
  bool _pushEnabled = false;
  bool _pushSupported = true; // TEMP: Force to true for testing

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
      // Get location
      final loc = await _locationService.getCurrentLocation();
      if (mounted) {
        setState(() => _currentLocation = loc);
      }
    } catch (e) {
      debugPrint('Location service error: $e');
      // Try to get from server
      try {
        final region = await _pocketbaseService.fetchRegionConfig();
        if (region != null && mounted) {
          setState(() {
            _currentLocation = LatLng(
              (region['lat'] as num).toDouble(),
              (region['long'] as num).toDouble(),
            );
          });
        }
      } catch (e2) {
        debugPrint('Failed to fetch region config: $e2');
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
          // _pushSupported = supported;
          _pushEnabled = enabled;
        });
      }
    } catch (e) {
      debugPrint('Push notification init error: $e');
    }
  }

  Future<void> _updateSubscriptions() async {
    final newGeohashes = _geohashService.getNeighborhoodForLocation(
      _currentLocation.latitude,
      _currentLocation.longitude,
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
    setState(() => _currentLocation = location);
    _updateSubscriptions();
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
        location: _currentLocation,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit report: $e'),
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
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 8,
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
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text('🧊', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'notICE',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                '${_reports.length} reports in area',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Telegram button (if configured)
                        if (_telegramLink != null) ...[
                          GestureDetector(
                            onTap: () => launchUrl(Uri.parse(_telegramLink!)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0088CC).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.telegram, size: 16, color: Color(0xFF0088CC)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Join',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0088CC),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // Push Alert button (if supported)
                        if (_pushSupported) ...[
                          GestureDetector(
                            onTap: _togglePushNotifications,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _pushEnabled
                                    ? Colors.orange.withValues(alpha: 0.2)
                                    : Colors.grey.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _pushEnabled ? Icons.notifications_active : Icons.notifications_off,
                                    size: 16,
                                    color: _pushEnabled ? Colors.orange : Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _pushEnabled ? 'Alerts' : 'Enable',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _pushEnabled ? Colors.orange : Colors.grey,
                                    ),
                                  ),
                                  if (_pushEnabled) ...[
                                    const SizedBox(width: 8),
                                    TextButton(
                                      onPressed: () => PushNotificationService.instance.testLocalNotification(),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text('Test', style: TextStyle(fontSize: 10, color: Colors.blue)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle, size: 8, color: Colors.green),
                              SizedBox(width: 4),
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Time filter chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _timeFilterOptions.entries.map((entry) {
                          final isSelected = _selectedTimeFilter == entry.key;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(entry.value),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _selectedTimeFilter = entry.key);
                                  _refreshReports();
                                }
                              },
                              selectedColor: Theme.of(context).colorScheme.primaryContainer,
                              showCheckmark: false,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              labelStyle: TextStyle(
                                fontSize: 12,
                                color: isSelected 
                                    ? Theme.of(context).colorScheme.onPrimaryContainer
                                    : null,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Location button
          Positioned(
            bottom: 100,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'location',
              onPressed: _centerOnLocation,
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),

      // Report button
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showReportForm,
        icon: const Icon(Icons.add_alert),
        label: const Text('Report'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
