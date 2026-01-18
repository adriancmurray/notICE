import 'dart:async';
import 'package:pocketbase/pocketbase.dart';
import 'package:app/config/app_config.dart';
import 'package:app/models/report.dart';
import 'package:app/services/device_fingerprint_service.dart';
import 'package:app/services/geohash_service.dart';
import 'package:app/services/vote_tracking_service.dart';

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

  /// Fetch the Telegram channel link from the server.
  /// 
  /// Returns the link (e.g., "https://t.me/noticeidahofalls") or null if not configured.
  Future<String?> fetchTelegramLink() async {
    try {
      final records = await _pb.collection('config').getList(
        page: 1,
        perPage: 1,
        filter: 'key = "telegram"',
      );

      if (records.items.isNotEmpty) {
        final value = records.items.first.data['value'];
        if (value is Map<String, dynamic> && value['link'] != null) {
          return value['link'] as String;
        }
      }
    } catch (e) {
      // Config not available
    }
    return null;
  }

  /// Fetch recent reports for a set of geohashes.
  /// 
  /// [sinceHours] filters to reports created within the last N hours.
  /// Default is 24 hours.
  Future<List<Report>> fetchReports({
    required Set<String> geohashes,
    int limit = 50,
    int sinceHours = 24,
  }) async {
    final geohashFilter = _geohashService.buildGeohashFilter(geohashes);
    
    // Calculate cutoff time
    final cutoff = DateTime.now().toUtc().subtract(Duration(hours: sinceHours));
    final timeFilter = 'created >= "${cutoff.toIso8601String()}"';
    
    // Combine filters
    final filter = '($geohashFilter) && $timeFilter';
    
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
    
    // Get device fingerprint for server-side rate limiting
    final fingerprint = await DeviceFingerprintService.instance.getFingerprint();

    final record = await _pb.collection('reports').create(
      body: {
        'geohash': geohash,
        'type': type.name,
        'description': description ?? '',
        'lat': lat,
        'long': long,
      },
      headers: {
        'X-Device-Fingerprint': fingerprint,
      },
    );

    return Report.fromRecord(record);
  }

  /// Confirm a report (increment confirmations count).
  /// 
  /// Throws if user has already voted on this report.
  Future<void> confirmReport(String reportId) async {
    final voteService = VoteTrackingService.instance;
    
    // Check if already voted
    if (await voteService.hasVoted(reportId)) {
      throw Exception('You have already voted on this report');
    }
    
    // Fetch current report to get current count
    final record = await _pb.collection('reports').getOne(reportId);
    final currentConfirmations = record.getIntValue('confirmations');
    
    await _pb.collection('reports').update(
      reportId,
      body: {'confirmations': currentConfirmations + 1},
    );
    
    // Record the vote
    await voteService.recordConfirmation(reportId);
  }

  /// Dispute a report (increment disputes count).
  /// 
  /// Throws if user has already voted on this report.
  Future<void> disputeReport(String reportId) async {
    final voteService = VoteTrackingService.instance;
    
    // Check if already voted
    if (await voteService.hasVoted(reportId)) {
      throw Exception('You have already voted on this report');
    }
    
    // Fetch current report to get current count
    final record = await _pb.collection('reports').getOne(reportId);
    final currentDisputes = record.getIntValue('disputes');
    
    await _pb.collection('reports').update(
      reportId,
      body: {'disputes': currentDisputes + 1},
    );
    
    // Record the vote
    await voteService.recordDispute(reportId);
  }

  /// Delete a report (admin only).
  Future<void> deleteReport(String reportId) async {
    await _pb.collection('reports').delete(reportId);
  }

  /// Dispose resources.
  void dispose() {
    unsubscribeFromGeohashes();
    _reportsController.close();
  }
}
