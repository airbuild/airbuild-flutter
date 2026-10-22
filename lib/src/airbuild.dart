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
      onUpdate: () => _performUpdate(update, platform),
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

  /// Performs the platform-specific update flow.
  ///
  /// On Android, downloads the APK to a temp file and triggers the system
  /// installer via a platform channel. On iOS, opens the install URL in the
  /// browser (Safari) since iOS does not allow sideloading.
  static Future<void> _performUpdate(UpdateInfo update, String platform) async {
    if (platform == 'ios') {
      final url = Uri.parse(update.installUrl ?? '');
      if (url.toString().isNotEmpty) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } else {
      // Android: download APK and trigger install
      final downloadUrl = update.downloadUrl;
      if (downloadUrl == null) {
        throw Exception('No download URL available for this update');
      }

      final client = _client!;
      if (update.buildId != null) {
        client.reportEvent(
          buildId: update.buildId!,
          event: 'download_started',
          platform: platform,
        );
      }

      final dir = await getTemporaryDirectory();
      final apkPath = '${dir.path}/airbuild_update.apk';
      await client.downloadApk(url: downloadUrl, outputPath: apkPath);

      if (update.buildId != null) {
        client.reportEvent(
          buildId: update.buildId!,
          event: 'install_started',
          platform: platform,
        );
      }

      // Trigger system installer via platform channel
      await _triggerApkInstall(apkPath);
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
