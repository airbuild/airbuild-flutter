import 'package:airbuild/src/update_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateInfo.fromJson', () {
    test('parses a "no update" response', () {
      final info = UpdateInfo.fromJson({'hasUpdate': false});
      expect(info.hasUpdate, isFalse);
      expect(info.latestVersion, isNull);
      expect(info.buildId, isNull);
      expect(info.isPasswordProtected, isFalse);
    });

    test('parses a full "update available" response', () {
      final info = UpdateInfo.fromJson({
        'hasUpdate': true,
        'latestVersion': '1.2.0',
        'latestBuildNumber': 42,
        'buildId': 'b_123',
        'releaseNotes': 'Bug fixes',
        'downloadUrl': 'https://airbuild.dev/api/sdk/download/abc',
        'installUrl': 'https://airbuild.dev/i/abc',
        'fileSizeBytes': 10485760,
        'iconUrl': 'https://airbuild.dev/icon.png',
        'minOsVersion': '14.0',
        'isPasswordProtected': true,
        'createdAt': '2024-01-01T00:00:00Z',
      });

      expect(info.hasUpdate, isTrue);
      expect(info.latestVersion, '1.2.0');
      expect(info.latestBuildNumber, 42);
      expect(info.buildId, 'b_123');
      expect(info.releaseNotes, 'Bug fixes');
      expect(info.downloadUrl, 'https://airbuild.dev/api/sdk/download/abc');
      expect(info.installUrl, 'https://airbuild.dev/i/abc');
      expect(info.fileSizeBytes, 10485760);
      expect(info.iconUrl, 'https://airbuild.dev/icon.png');
      expect(info.minOsVersion, '14.0');
      expect(info.isPasswordProtected, isTrue);
      expect(info.createdAt, '2024-01-01T00:00:00Z');
    });

    test('defaults isPasswordProtected to false when omitted', () {
      final info = UpdateInfo.fromJson({'hasUpdate': true});
      expect(info.isPasswordProtected, isFalse);
    });
  });

  group('UpdateInfo.fileSizeDisplay', () {
    test('returns empty string when fileSizeBytes is null', () {
      const info = UpdateInfo(hasUpdate: true);
      expect(info.fileSizeDisplay, '');
    });

    test('returns empty string when fileSizeBytes is zero or negative', () {
      const info = UpdateInfo(hasUpdate: true, fileSizeBytes: 0);
      expect(info.fileSizeDisplay, '');
    });

    test('formats bytes', () {
      const info = UpdateInfo(hasUpdate: true, fileSizeBytes: 512);
      expect(info.fileSizeDisplay, '512 B');
    });

    test('formats kilobytes', () {
      const info = UpdateInfo(hasUpdate: true, fileSizeBytes: 2048);
      expect(info.fileSizeDisplay, '2.0 KB');
    });

    test('formats megabytes', () {
      const info = UpdateInfo(hasUpdate: true, fileSizeBytes: 25 * 1024 * 1024);
      expect(info.fileSizeDisplay, '25.0 MB');
    });

    test('formats gigabytes without a decimal when >= 100 units', () {
      // 150 MB worth of KB converted up through units to land on MB with a
      // value >= 100, which should drop the decimal place.
      const info = UpdateInfo(hasUpdate: true, fileSizeBytes: 150 * 1024 * 1024);
      expect(info.fileSizeDisplay, '150 MB');
    });
  });
}
