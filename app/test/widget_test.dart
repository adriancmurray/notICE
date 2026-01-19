import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/report.dart';

void main() {
  group('Report', () {
    test('fromRecord creates valid Report', () {
      // Mock a minimal record-like map for testing
      final report = Report(
        id: 'abc123',
        geohash: '9xj5ns',
        type: ReportType.danger,
        description: 'Ice on road',
        lat: 43.4926,
        long: -112.0401,
        created: DateTime.now(),
        confirmations: 2,
        disputes: 0,
      );

      expect(report.id, 'abc123');
      expect(report.type, ReportType.danger);
      expect(report.isDisputed, false);
      expect(report.credibilityScore, 2);
    });

    test('isDisputed returns true when disputes >= 2', () {
      final report = Report(
        id: 'test1',
        geohash: '9xj5ns',
        type: ReportType.warning,
        lat: 43.0,
        long: -112.0,
        created: DateTime.now(),
        disputes: 2,
      );
      expect(report.isDisputed, true);
    });

    test('credibilityScore is confirmations minus disputes', () {
      final report = Report(
        id: 'test2',
        geohash: '9xj5ns',
        type: ReportType.safe,
        lat: 43.0,
        long: -112.0,
        created: DateTime.now(),
        confirmations: 5,
        disputes: 2,
      );
      expect(report.credibilityScore, 3);
    });
  });

  group('ReportType', () {
    test('displayName returns readable strings', () {
      expect(ReportType.danger.displayName, 'Danger');
      expect(ReportType.warning.displayName, 'Warning');
      expect(ReportType.safe.displayName, 'All Clear');
    });

    test('emoji returns correct emoji', () {
      expect(ReportType.danger.emoji, '🚨');
      expect(ReportType.warning.emoji, '⚠️');
      expect(ReportType.safe.emoji, '✅');
    });

    test('colorValue returns valid color values', () {
      expect(ReportType.danger.colorValue, 0xFFE53935);
      expect(ReportType.warning.colorValue, 0xFFFFA726);
      expect(ReportType.safe.colorValue, 0xFF66BB6A);
    });
  });
}
