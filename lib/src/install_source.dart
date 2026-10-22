import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The package name Google Play installs apps under — the value returned by
/// `PackageManager.getInstallSourceInfo().installingPackageName` for
/// Play-installed apps.
const String playStorePackageName = 'com.android.vending';

const MethodChannel _channel = MethodChannel('dev.airbuild.airbuild/install');

Future<String?>? _cachedInstaller;

/// The package name of the app/store that installed this app on the device
/// (Android only).
///
/// Common values:
/// - `com.android.vending` — Google Play Store
/// - `com.sec.android.app.samsungapps` — Samsung Galaxy Store
/// - `com.amazon.venezia` — Amazon Appstore
/// - `null` — sideloads (ADB, direct APK, AirBuild OTA installs), preloaded
///   apps, emulators, and every non-Android platform
///
/// The result is cached for the lifetime of the process — the installer of a
/// running app cannot change.
Future<String?> installerPackageName() {
  if (!Platform.isAndroid) return Future<String?>.value();
  return _cachedInstaller ??= _lookupInstaller();
}

/// Whether this running build was installed from the Google Play Store.
///
/// Always `false` on non-Android platforms, on sideloaded/ADB installs, and
/// when the install source cannot be determined — the check fails open so an
/// unknown source never disables updates.
Future<bool> isPlayStoreInstall() async =>
    (await installerPackageName()) == playStorePackageName;

Future<String?> _lookupInstaller() async {
  try {
    return await _channel.invokeMethod<String>('getInstallerPackageName');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// Clears the cached installer lookup. Exposed for tests only.
@visibleForTesting
void debugResetInstallerCache() => _cachedInstaller = null;
