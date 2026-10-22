import 'package:airbuild/src/airbuild_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AirBuildConfig', () {
    test('defaults baseUrl to the hosted AirBuild server', () {
      final config = AirBuildConfig(distributionKey: 'dk_test');
      expect(config.distributionKey, 'dk_test');
      expect(config.baseUrl, 'https://airbuild.dev');
    });

    test('accepts a custom baseUrl for self-hosted servers', () {
      final config = AirBuildConfig(
        distributionKey: 'dk_test',
        baseUrl: 'https://staging.airbuild.dev',
      );
      expect(config.baseUrl, 'https://staging.airbuild.dev');
    });

    test('throws if distributionKey does not start with dk_', () {
      expect(
        () => AirBuildConfig(distributionKey: 'not-a-valid-key'),
        throwsA(isA<AssertionError>()),
      );
    });

    test('checkUpdateUri builds the expected query parameters', () {
      final config = AirBuildConfig(distributionKey: 'dk_test');
      final uri = config.checkUpdateUri(version: '1.0.0', platform: 'android');

      expect(uri.path, '/api/sdk/check-update');
      expect(uri.queryParameters['key'], 'dk_test');
      expect(uri.queryParameters['version'], '1.0.0');
      expect(uri.queryParameters['platform'], 'android');
    });

    test('reportEventUri points at the report-event endpoint', () {
      final config = AirBuildConfig(
        distributionKey: 'dk_test',
        baseUrl: 'https://staging.airbuild.dev',
      );
      expect(
        config.reportEventUri.toString(),
        'https://staging.airbuild.dev/api/sdk/report-event',
      );
    });
  });
}
