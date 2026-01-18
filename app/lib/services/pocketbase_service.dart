import 'dart:async';
import 'package:pocketbase/pocketbase.dart';
import 'package:app/config/app_config.dart';
import 'package:app/models/report.dart';
import 'package:app/services/geohash_service.dart';

/// Service for PocketBase backend communication.
class PocketbaseService {
  PocketbaseService._();
  static final PocketbaseService instance = PocketbaseService._();

  late final PocketBase _pb;
  final _geohashService = GeohashService.instance;

  /// Active realtime subscriptions.
  final Map<String, UnsubscribeFunc> _subscriptions = {};

  /// Stream controller for incoming reports.
  final _reportsController = StreamController<Report>.broadcast();

  /// Stream of reports from realtime subscriptions.
  Stream<Report> get reportsStream => _reportsController.stream;

  /// Initialize the PocketBase client.
  Future<void> initialize() async {
    _pb = PocketBase(AppConfig.pocketbaseUrl);
    
    // For anonymous auth, we could create anonymous users here.
    // For now, the API rules allow public read/create.
  }

  /// Fetch the region configuration from the server.
  /// 
  /// Returns {name, lat, long, zoom} or null if not configured.
  Future<Map<String, dynamic>?> fetchRegionConfig() async {
    try {
      final records = await _pb.collection('config').getList(
        page: 1,
        perPage: 1,
        filter: 'key = "region"',
      );

      if (records.items.isNotEmpty) {
        final value = records.items.first.data['value'];
        if (value is Map<String, dynamic>) {
          return value;
        }
      }
    } catch (e) {
      // Config not available, will use fallback
    }
    return null;
  }

  /// Fetch recent reports for a set of geohashes.
  Future<List<Report>> fetchReports({
    required Set<String> geohashes,
    int limit = 50,
  }) async {
    final filter = _geohashService.buildGeohashFilter(geohashes);
    
    final records = await _pb.collection('reports').getList(
      page: 1,
      perPage: limit,
      filter: filter,
      sort: '-created',
    );

    return records.items.map(Report.fromRecord).toList();
  }

  /// Subscribe to realtime updates for a set of geohashes.
  /// 
  /// Call [unsubscribeFromGeohashes] when location changes or on dispose.
  Future<void> subscribeToGeohashes(Set<String> geohashes) async {
    // Unsubscribe from any existing subscriptions
    await unsubscribeFromGeohashes();

    // Build the filter for this subscription
    final filter = _geohashService.buildGeohashFilter(geohashes);

    // Subscribe to the reports collection
    final unsubscribe = await _pb.collection('reports').subscribe(
      '*',
      (e) {
        if (e.action == 'create' && e.record != null) {
          final report = Report.fromRecord(e.record!);
          // Only emit if the report matches our geohash filter
          if (geohashes.any((gh) => report.geohash.startsWith(gh))) {
            _reportsController.add(report);
          }
        }
      },
      filter: filter,
    );

    _subscriptions['reports'] = unsubscribe;
  }

  /// Unsubscribe from all realtime subscriptions.
  Future<void> unsubscribeFromGeohashes() async {
    for (final unsubscribe in _subscriptions.values) {
      await unsubscribe();
    }
    _subscriptions.clear();
  }

  /// Submit a new report.
  Future<Report> submitReport({
    required double lat,
    required double long,
    required ReportType type,
    String? description,
  }) async {
    final geohash = _geohashService.encode(lat, long);

    final record = await _pb.collection('reports').create(
      body: {
        'geohash': geohash,
        'type': type.name,
        'description': description ?? '',
        'lat': lat,
        'long': long,
      },
    );

    return Report.fromRecord(record);
  }

  /// Dispose resources.
  void dispose() {
    unsubscribeFromGeohashes();
    _reportsController.close();
  }
}
