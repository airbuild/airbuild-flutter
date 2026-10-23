import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'airbuild_config.dart';
import 'update_info.dart';

/// HTTP client for the AirBuild SDK API.
///
/// Wraps the two public SDK endpoints:
/// - `GET /api/sdk/check-update`
/// - `POST /api/sdk/report-event`
///
/// All methods are best-effort: network errors are swallowed and reported via
/// the returned `null`/`false` rather than throwing, so the host app never
/// crashes because of the SDK.
class AirBuildClient {
  /// Creates a client bound to the given [config].
  AirBuildClient(this.config);

  final AirBuildConfig config;
  final http.Client _httpClient = http.Client();

  /// Calls `GET /api/sdk/check-update` and returns the parsed [UpdateInfo].
  ///
  /// [buildNumber] is the currently installed build's build number
  /// (versionCode / CFBundleVersion), when known — it lets the server
  /// distinguish same-version builds (e.g. `1.0.0+1` vs `1.0.0+2`).
  ///
  /// Returns an [UpdateInfo] with `hasUpdate: false` if the request fails for
  /// any reason, so callers can treat the result uniformly.
  Future<UpdateInfo> checkForUpdate({
    required String version,
    required String platform,
    String? buildNumber,
  }) async {
    final uri = config.checkUpdateUri(
      version: version,
      platform: platform,
      buildNumber: buildNumber,
    );
    try {
      final response = await _httpClient.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'AirBuild-Flutter-SDK/0.4.0',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return const UpdateInfo(hasUpdate: false);
      }
      return UpdateInfo.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on Exception {
      return const UpdateInfo(hasUpdate: false);
    }
  }

  /// Reports an analytics event to `POST /api/sdk/report-event`.
  ///
  /// [event] should be one of: `update_prompt_shown`, `update_accepted`,
  /// `update_declined`, `download_started`, `download_failed`,
  /// `install_started`, `install_failed`.
  ///
  /// Returns `true` if the server accepted the event. Failures are swallowed
  /// and reported as `false` so analytics never disrupts the user flow.
  Future<bool> reportEvent({
    required String buildId,
    required String event,
    String? platform,
    String? udid,
  }) async {
    try {
      final response = await _httpClient
          .post(
            config.reportEventUri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': 'AirBuild-Flutter-SDK/0.4.0',
            },
            body: jsonEncode({
              'key': config.distributionKey,
              'buildId': buildId,
              'event': event,
              if (platform != null) 'platform': platform,
              if (udid != null) 'udid': udid,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200 || response.statusCode == 201;
    } on Exception {
      return false;
    }
  }

  /// Downloads the APK at [url] to a temporary file and returns its path.
  ///
  /// Throws on failure so the caller can surface an error to the tester.
  Future<String> downloadApk({
    required String url,
    required String outputPath,
    void Function(int received, int total)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _httpClient.send(request);

    if (response.statusCode != 200) {
      // Drain the body so the connection can be reused/closed cleanly.
      await response.stream.drain<void>();
      throw HttpException('Download failed with status ${response.statusCode}');
    }

    final total = response.contentLength ?? -1;
    final output = File(outputPath);
    final sink = output.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null) {
          // A throwing host-app progress callback must not break the download.
          try {
            onProgress(received, total);
          } catch (_) {}
        }
      }
    } catch (e) {
      // Close the sink then remove the partial file so it can't be installed.
      await sink.flush().catchError((_) {});
      await sink.close().catchError((_) {});
      await output.delete().catchError((_) => output);
      rethrow;
    } finally {
      await sink.flush().catchError((_) {});
      await sink.close().catchError((_) {});
    }
    return outputPath;
  }
}
