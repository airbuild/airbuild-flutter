/// Configuration for the AirBuild SDK.
///
/// Holds the public distribution key (per-app, non-secret) and the optional
/// base URL of the AirBuild server. The default base URL points to the hosted
/// AirBuild service at https://airbuild.dev.
class AirBuildConfig {
  /// Creates an AirBuild configuration.
  ///
  /// [distributionKey] is the public key for your app, in the form `dk_xxx`.
  /// It is safe to ship in client apps — it is not a secret.
  ///
  /// [baseUrl] defaults to `https://airbuild.dev`. Override it only when
  /// running against a self-hosted AirBuild server.
  AirBuildConfig({
    required this.distributionKey,
    this.baseUrl = 'https://airbuild.dev',
  }) : assert(
          distributionKey.startsWith('dk_'),
          'distributionKey must start with "dk_"',
        );

  /// The public distribution key for the app (e.g. `dk_a1b2c3d4e5f6`).
  final String distributionKey;

  /// Base URL of the AirBuild server, without a trailing slash.
  final String baseUrl;

  /// Returns the full URL for the check-update endpoint.
  Uri checkUpdateUri({
    required String version,
    required String platform,
    String? buildNumber,
  }) {
    return Uri.parse('$baseUrl/api/sdk/check-update').replace(
      queryParameters: {
        'key': distributionKey,
        'version': version,
        'platform': platform,
        if (buildNumber != null && buildNumber.isNotEmpty) 'build': buildNumber,
      },
    );
  }

  /// Returns the full URL for the report-event endpoint.
  Uri get reportEventUri => Uri.parse('$baseUrl/api/sdk/report-event');
}
