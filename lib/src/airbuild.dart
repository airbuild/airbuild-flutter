import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'airbuild_client.dart';
import 'airbuild_config.dart';
import 'update_dialog.dart';
import 'update_info.dart';

/// AirBuild Distribution SDK for Flutter.
///
/// This SDK checks AirBuild install links for new binary builds and prompts
/// the tester to install. It is NOT a CodePush SDK — it only detects new
/// uploaded builds, it does not patch JS/Dart code at runtime.
///
/// Usage:
///
/// ```dart
/// void main() {
///   AirBuild.configure(distributionKey: 'dk_a1b2c3d4e5f6');
///   runApp(MyApp());
/// }
///
/// // Later, e.g. on app start or a "check for updates" button:
/// await AirBuild.checkForUpdates(
///   context: context,
///   currentVersion: '1.0.0',
/// );
/// ```
class AirBuild {
  AirBuild._();

  static AirBuildConfig? _config;
  static AirBuildClient? _client;

  /// Configures the SDK with the app's distribution key.
  ///
  /// Call this once at app startup, before [checkForUpdates].
  ///
  /// [distributionKey] is the public key for your app (dk_xxx). It is safe to
  /// embed in distributed apps — it is not a secret.
  ///
  /// [baseUrl] defaults to `https://airbuild.dev`. Override it when running
  /// against a self-hosted AirBuild server.
  static void configure({
    required String distributionKey,
    String baseUrl = 'https://airbuild.dev',
  }) {
    _config = AirBuildConfig(
      distributionKey: distributionKey,
      baseUrl: baseUrl,
    );
    _client = AirBuildClient(_config!);
  }

  /// The current configuration, or null if [configure] has not been called.
  static AirBuildConfig? get config => _config;

  /// Checks the AirBuild server for a newer build and shows a default update
  /// dialog if one is available.
  ///
  /// The SDK handles the entire flow:
  /// 1. Calls `GET /api/sdk/check-update` with the current version and platform.
  /// 2. If an update is available, shows an [UpdateDialog] with version, release
  ///    notes, and Update/Later buttons.
  /// 3. On "Update" tap:
  ///    - Android: downloads the APK and triggers the system installer.
  ///    - iOS: opens the install URL in the browser (Safari).
  /// 4. Reports analytics events (prompt shown, accepted, declined, etc.).
  ///
  /// [context] is the build context used to show the dialog. If null, the
  /// method will check for updates but not show a dialog — it returns the
  /// [UpdateInfo] so the app can build its own UI.
  ///
  /// [currentVersion] is the version string of the currently running app
  /// (e.g. "1.0.0"). The SDK compares this against the latest build version
  /// on the server.
  ///
  /// [currentBuildNumber] is the build number of the currently running app
  /// (Android `versionCode` / iOS `CFBundleVersion`). When omitted, the SDK
  /// reads it automatically via `package_info_plus` so the server can
  /// distinguish same-version builds (e.g. `1.0.0+1` vs `1.0.0+2`). Pass an
  /// explicit value only to override the auto-detected one.
  static Future<UpdateInfo> checkForUpdates({
    BuildContext? context,
    required String currentVersion,
    String? currentBuildNumber,
    String? appName,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError(
        'AirBuild.configure() must be called before checkForUpdates()',
      );
    }

    final platform = Platform.isIOS ? 'ios' : 'android';
    final buildNumber = currentBuildNumber ?? await _installedBuildNumber();

    final update = await client.checkForUpdate(
      version: currentVersion,
      platform: platform,
      buildNumber: buildNumber,
    );

    if (!update.hasUpdate || context == null) {
      return update;
    }

    // Report prompt shown
    if (update.buildId != null) {
      client.reportEvent(
        buildId: update.buildId!,
        event: 'update_prompt_shown',
        platform: platform,
      );
    }

    // Show the default dialog
    final accepted = await showUpdateDialog(
      context,
      update: update,
      appName: appName,
      onUpdate: () => installUpdate(update),
    );

    if (accepted == true) {
      if (update.buildId != null) {
        client.reportEvent(
          buildId: update.buildId!,
          event: 'update_accepted',
          platform: platform,
        );
      }
    } else {
      if (update.buildId != null) {
        client.reportEvent(
          buildId: update.buildId!,
          event: 'update_declined',
          platform: platform,
        );
      }
    }

    return update;
  }

  /// Runs the platform install flow for [update] — the same flow the
  /// built-in dialog triggers when the tester taps "Update".
  ///
  /// - **Android**: downloads the APK to a temp file *inside the app* (no
  ///   browser redirect) and installs it. On Android 12+ (API 31+) the
  ///   install goes through a `PackageInstaller` session — when your app is
  ///   its own installer of record, the update applies with no confirmation
  ///   sheet at all; otherwise the standard install sheet opens and the
  ///   user taps "Install". On Android 11 and below the install sheet
  ///   always opens. Android may also ask the user once to allow installs
  ///   from your app (required on API 26+). [onProgress] receives
  ///   `(bytesReceived, totalBytes)` during the download — `totalBytes` is
  ///   `-1` when the server doesn't send a content length — so custom UIs
  ///   can show a progress bar.
  /// - **iOS**: opens [UpdateInfo.installUrl] in Safari, since iOS does not
  ///   allow sideloading IPAs in-app.
  ///
  /// Use this from a custom update UI — e.g. the `onUpdate` callback of
  /// [showUpdateDialog], or your own bottom sheet — after a headless
  /// `checkForUpdates()` call (one without `context`):
  ///
  /// ```dart
  /// final info = await AirBuild.checkForUpdates(currentVersion: '1.0.0');
  /// if (info.hasUpdate) {
  ///   await AirBuild.installUpdate(info);
  /// }
  /// ```
  ///
  /// `download_started` / `install_started` analytics events are reported
  /// automatically, exactly as with the built-in dialog, and
  /// `download_failed` / `install_failed` are reported when the
  /// corresponding step throws.
  static Future<void> installUpdate(
    UpdateInfo update, {
    void Function(int received, int total)? onProgress,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError(
        'AirBuild.configure() must be called before installUpdate()',
      );
    }

    final platform = Platform.isIOS ? 'ios' : 'android';
    if (platform == 'ios') {
      final installUrl = update.installUrl;
      final url = installUrl == null ? null : Uri.tryParse(installUrl);
      if (url == null ||
          !['https', 'http', 'itms-services'].contains(url.scheme)) {
        throw Exception(
          'No valid install URL available for this update '
          '(expected an https or itms-services URL)',
        );
      }
      try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (e) {
        throw Exception('Could not open the iOS install URL: $e');
      }
      return;
    }

    // Android: download APK in-app and trigger the system installer
    final downloadUrl = update.downloadUrl;
    if (downloadUrl == null) {
      throw Exception('No download URL available for this update');
    }

    final buildId = update.buildId;
    if (buildId != null) {
      client.reportEvent(
        buildId: buildId,
        event: 'download_started',
        platform: platform,
      );
    }

    final dir = await getTemporaryDirectory();
    final apkPath = '${dir.path}/airbuild_update.apk';
    // Remove a stale APK from a previous run before downloading — a failed
    // install can otherwise leave an old file behind that later gets picked
    // up if the new download fails part-way.
    await File(apkPath).delete().catchError((_) => File(apkPath));

    try {
      await client.downloadApk(
        url: downloadUrl,
        outputPath: apkPath,
        onProgress: onProgress,
      );
      // Guard against a redirect/error page being saved as the "APK" —
      // Android APKs are ZIP archives and always start with the PK magic.
      final file = File(apkPath);
      final header =
          await file.openRead(0, 2).expand((chunk) => chunk).toList();
      if (header.length < 2 || header[0] != 0x50 || header[1] != 0x4B) {
        await file.delete().catchError((_) => file);
        throw Exception(
          'Downloaded file is not a valid APK (unexpected file signature)',
        );
      }
    } catch (e) {
      if (buildId != null) {
        client.reportEvent(
          buildId: buildId,
          event: 'download_failed',
          platform: platform,
        );
      }
      rethrow;
    }

    if (buildId != null) {
      client.reportEvent(
        buildId: buildId,
        event: 'install_started',
        platform: platform,
      );
    }

    // Trigger system installer via platform channel
    try {
      await _triggerApkInstall(apkPath);
    } catch (e) {
      if (buildId != null) {
        client.reportEvent(
          buildId: buildId,
          event: 'install_failed',
          platform: platform,
        );
      }
      rethrow;
    }
  }

  /// Reads the host app's own build number via `package_info_plus`
  /// (`versionCode` on Android, `CFBundleVersion` on iOS). Returns null when
  /// the plugin is unavailable — the server then falls back to version-name
  /// comparison only.
  static Future<String?> _installedBuildNumber() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.buildNumber.isNotEmpty ? info.buildNumber : null;
    } on Exception {
      return null;
    }
  }

  /// Calls the native platform channel to trigger the Android system installer.
  static Future<void> _triggerApkInstall(String apkPath) async {
    // Uses a basic method channel to the native plugin.
    // The Android side picks up the file path and creates an Intent.
    const channel = MethodChannel('dev.airbuild.airbuild/install');
    try {
      await channel.invokeMethod('installApk', {'path': apkPath});
    } on MissingPluginException {
      // Native plugin not registered — this happens on non-Android platforms
      // or when the plugin hasn't been added to the app. Re-throw with a
      // clearer message.
      throw Exception(
        'AirBuild native plugin not found. Ensure the AirBuild Flutter plugin '
        'is properly added to your pubspec.yaml and the app was rebuilt.',
      );
    }
  }
}
