# Changelog

## 0.3.1 - 2026-10-22

### Fixed
- README updated: Install snippet now shows the correct `^0.3.0` constraint.

## 0.3.0 - 2026-10-20

### Added
- `AirBuildCodePushOverlay` — a drop-in widget that runs the whole manual
  CodePush lifecycle: checks on launch, on app resume, and on a timer
  (default 4h), downloads available patches, and shows a "restart to
  apply" banner. Configurable via `AirBuildCodePushConfig` (channel,
  `checkOnLaunch`/`checkOnResume`/`checkInterval`, `onRestart`,
  `bannerBuilder`, `onUpdateReady`). The banner re-appears only when a
  *different* patch is staged, so dismissed prompts don't nag.
- `showDebugBar` overlay option — a thin status strip showing the live
  CodePush state for internal/dev builds.
- `disableOnPlayStoreInstalls` on `AirBuildCodePush` and
  `AirBuildCodePushConfig` — skips patch checks/downloads when the running
  build was installed from Google Play (`com.android.vending`), so OTA
  patches apply only to AirBuild-distributed/sideloaded installs. Fails
  open on undeterminable install sources. Does not affect the engine's
  `auto_update` boot thread — combine with `auto_update: false` for a
  complete opt-out.
- `installerPackageName()` / `isPlayStoreInstall()` helpers
  (`airbuild_code_push.dart` export) for reading the Android install
  source. New `getInstallerPackageName` method on the Android plugin's
  method channel; no iOS change needed.
- `AirBuildCodePush` now accepts injectable `updater` /
  `playStoreInstallProbe` (test-only seams).
- Widget + unit tests covering the overlay lifecycle, banner
  dismiss/re-show behavior, resume checks, and Play-Store gating
  (33 tests total).

## 0.2.0 - 2026-09-12

### Added
- New `airbuild_code_push.dart` library: `AirBuildCodePush`, a thin wrapper
  around Shorebird's `shorebird_code_push` package (`checkForUpdate()`,
  `update()`, `currentPatch()`, `nextPatch()`, `isAvailable`) that maps
  AirBuild channel names (`"production"`, `"staging"`, custom) onto
  Shorebird's `UpdateTrack` concept.
- `showRestartBanner()` — a `MaterialBanner`-based prompt for telling
  testers a patch was downloaded and needs a restart to apply.
- Re-exports `Patch`, `UpdateStatus`, `UpdateTrack`, and related exceptions
  from `shorebird_code_push` for convenience.
- `example/lib/main.dart` now includes a CodePush usage example alongside
  the existing binary-distribution example.
- `INTERNET` + `REQUEST_INSTALL_PACKAGES` permissions in the plugin's
  `AndroidManifest.xml` so the merged manifest of host apps can download
  and self-install APKs on Android 8+.
- `checkForUpdates` sends the app's build number as `?build=` so the
  server can distinguish same-version builds (e.g. `1.0.0+1` vs
  `1.0.0+2`) and stops re-prompting devices already on the latest build.
  Auto-detected via `package_info_plus`; `currentBuildNumber` overrides it.
- Unit tests for `AirBuildConfig`, `UpdateInfo`, byte-size formatting, and
  the CodePush channel→`UpdateTrack` mapping (20 tests).
- GitHub Actions CI workflow (`flutter analyze`, `flutter test`).

### Changed
- **Minimum SDK raised** to Dart `>=3.5.4` / Flutter `>=3.24.5` (from
  `>=2.17.0` / `>=3.0.0`), to satisfy `shorebird_code_push`'s own minimum
  constraints. Only affects apps that import the new
  `airbuild_code_push.dart` library — `airbuild.dart` (binary distribution)
  is otherwise unchanged.
- Fixed a pre-existing missing import (`package:flutter/services.dart`)
  that caused `MethodChannel`/`MissingPluginException` analysis errors in
  `airbuild.dart`.

## 0.1.0 - 2026-09-02

### Added
- Initial release of the AirBuild Flutter Distribution SDK.
- `AirBuild.configure(distributionKey, baseUrl?)` for one-time setup.
- `AirBuild.checkForUpdates(context, currentVersion)` to check for new builds.
- Default update dialog with app icon, version, release notes, and Update/Later buttons.
- Android: APK download + system installer via platform channel and FileProvider.
- iOS: Opens install URL in Safari via url_launcher.
- Analytics event reporting (prompt shown, accepted, declined, download started, install started).
- Example app in `example/`.
