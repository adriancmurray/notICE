import 'package:pocketbase/pocketbase.dart';

/// Report severity types.
enum ReportType {
  danger,
  warning,
  safe;

  String get displayName {
    switch (this) {
      case ReportType.danger:
        return 'Danger';
      case ReportType.warning:
        return 'Warning';
      case ReportType.safe:
        return 'All Clear';
    }
  }

  String get emoji {
    switch (this) {
      case ReportType.danger:
        return '🚨';
      case ReportType.warning:
        return '⚠️';
      case ReportType.safe:
        return '✅';
    }
  }

  /// Marker color for map display.
  int get colorValue {
    switch (this) {
      case ReportType.danger:
        return 0xFFE53935; // Red
      case ReportType.warning:
        return 0xFFFFA726; // Orange
      case ReportType.safe:
        return 0xFF66BB6A; // Green
    }
  }
}

/// A safety report submitted by a user.
class Report {
  final String id;
  final String geohash;
  final ReportType type;
  final String? description;
  final double lat;
  final double long;
  final DateTime created;

  const Report({
    required this.id,
    required this.geohash,
    required this.type,
    this.description,
    required this.lat,
    required this.long,
    required this.created,
  });

  /// Parse from PocketBase record.
  factory Report.fromRecord(RecordModel record) {
    return Report(
      id: record.id,
      geohash: record.getStringValue('geohash'),
      type: ReportType.values.firstWhere(
        (t) => t.name == record.getStringValue('type'),
        orElse: () => ReportType.warning,
      ),
      description: record.getStringValue('description'),
      lat: record.getDoubleValue('lat'),
      long: record.getDoubleValue('long'),
      created: DateTime.tryParse(record.created) ?? DateTime.now(),
    );
  }

  /// Convert to map for PocketBase submission.
  Map<String, dynamic> toJson() {
    return {
      'geohash': geohash,
      'type': type.name,
      'description': description,
      'lat': lat,
      'long': long,
    };
  }

  /// Time since report was created.
  String get timeAgo {
    final diff = DateTime.now().difference(created);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
