# AirBuild Flutter SDK

Flutter SDK for two independent AirBuild features — use either or both:

| Library | Feature | What it does |
| ------- | ------- | ------------ |
| `package:airbuild/airbuild.dart` | **Build distribution** | Checks AirBuild for a **new binary build** (APK/IPA) and prompts the tester to install it |
| `package:airbuild/airbuild_code_push.dart` | **CodePush** | Receives **Dart-only patches** that apply on top of the installed build — no store re-submission |

These are separate concerns: the update check asks "is there a newer *build*?", CodePush asks "is there a *patch* for this build?". Apps that don't use CodePush never import `airbuild_code_push.dart`.

## Installation

```yaml
dependencies:
  airbuild: ^0.4.1
```

```bash
flutter pub get
```

## Binary build update check

Call `AirBuild.configure()` once at startup, then `checkForUpdates()` anywhere:

```dart
import 'package:airbuild/airbuild.dart';

void main() {
  AirBuild.configure(
    distributionKey: 'dk_a1b2c3d4e5f6', // from the AirBuild dashboard
    // baseUrl: 'https://airbuild.dev', // optional — override for self-hosted servers
  );
  runApp(const MyApp());
}
```

```dart
// e.g. on app start or behind a "Check for Updates" button:
final info = await AirBuild.checkForUpdates(
  context: context,           // shows the built-in dialog; omit for a headless check
  currentVersion: '1.0.0',    // your app's version
  appName: 'My App',          // optional — dialog title becomes "My App update available"
);
```

The SDK handles the whole flow: checks the server → shows a dialog with the app icon, new version, file size and release notes → on "Update", **Android** downloads the APK and triggers the system installer, **iOS** opens the install link in Safari (no sideloading on iOS). Analytics events (`update_prompt_shown`, `update_accepted`, `update_declined`, `download_started`, `install_started`) are reported automatically.

The **distribution key** (`dk_xxx`) is a public identifier — safe to embed, not a secret.

### `checkForUpdates` parameters

| Parameter | Required | Description |
| --------- | -------- | ----------- |
| `currentVersion` | yes | Your app's version string (e.g. `'1.0.0'`). Compared against the latest build on the server. |
| `context` | no | Build context used to show the default dialog. Omit it to check silently and build your own UI from the returned `UpdateInfo`. |
| `currentBuildNumber` | no | Android `versionCode` / iOS `CFBundleVersion`. Auto-detected via `package_info_plus` when omitted — lets the server distinguish same-version builds (`1.0.0+1` vs `1.0.0+2`). |
| `appName` | no | App name shown in the dialog title. |

### `UpdateInfo`

`checkForUpdates` always returns an `UpdateInfo`, whether or not a dialog was shown:

| Field | Type | Description |
| ----- | ---- | ----------- |
| `hasUpdate` | `bool` | `true` when a newer build exists — the other fields are only set then |
| `latestVersion` | `String?` | Version of the latest build (e.g. `1.2.0`) |
| `latestBuildNumber` | `int?` | Build number of the latest build |
| `buildId` | `String?` | Server-side build id |
| `releaseNotes` | `String?` | Release notes for the build |
| `downloadUrl` | `String?` | Direct APK download URL (Android only) |
| `installUrl` | `String?` | Browser install URL (iOS — the SDK opens it in Safari) |
| `fileSizeBytes` | `int?` | Artifact size in bytes |
| `fileSizeDisplay` | `String` | Human-readable size, e.g. `"24.3 MB"` |
| `iconUrl` | `String?` | App icon shown in the dialog |
| `minOsVersion` | `String?` | Minimum OS version required |
| `isPasswordProtected` | `bool` | Build needs a password — handled by the web install flow, not the SDK |
| `createdAt` | `String?` | ISO timestamp of when the build was uploaded |

### Custom update UI

Omit `context` to skip the built-in dialog and render `UpdateInfo` however you like:

```dart
final info = await AirBuild.checkForUpdates(currentVersion: '1.0.0');
if (info.hasUpdate) {
  // e.g. show a bottom sheet with info.latestVersion,
  // info.releaseNotes, info.fileSizeDisplay, info.iconUrl, …
}
```

To reuse the SDK's dialog but hook the buttons yourself, call `showUpdateDialog` directly, and use `AirBuild.installUpdate` for the install — on Android it downloads the APK **inside the app** (no browser redirect) and launches the system installer; on iOS it opens the install URL in Safari:

```dart
final accepted = await showUpdateDialog(
  context,
  update: info,
  appName: 'My App',
  onUpdate: () => AirBuild.installUpdate(info),
  onLater: () {/* optional — defaults to dismissing */},
);
// accepted == true → user tapped Update, false → Later, null → dismissed
```

`installUpdate` accepts an `onProgress: (received, total)` callback so a custom UI can show download progress during the APK download. `total` is `-1` when the server doesn't send a content length — check `total > 0` before computing a percentage:

```dart
await AirBuild.installUpdate(
  info,
  onProgress: (received, total) {
    if (total > 0) print('${(received / total * 100).round()}%');
  },
);
```

`UpdateDialog` is also exported as a widget if you'd rather embed it in your own route or sheet. `download_started`/`install_started` analytics events are reported automatically (`download_failed`/`install_failed` on failure).

**Android:** no setup needed — `INTERNET`, `REQUEST_INSTALL_PACKAGES`, `UPDATE_PACKAGES_WITHOUT_USER_ACTION`, and the `FileProvider` are declared by the plugin. On first install, Android may ask the user to allow installs from your app (required on API 26+). On Android 12+ (API 31+) updates install through a `PackageInstaller` session — when your app is its own installer of record, the update applies with **no confirmation sheet at all**; otherwise the normal system install sheet appears. On Android 11 and below, the system installer sheet always opens (the user taps "Install").
**iOS:** no setup needed.

## CodePush (OTA Dart patches)

> **Prerequisite:** your app binary must be built by `airbuild codepush flutter release` — the AirBuild CLI compiles the OTA updater runtime into your app. A plain `flutter build` does not contain the updater. See the [Flutter CodePush guide](https://docs.airbuild.dev/guides/codepush-flutter/) for CLI setup.

### How patching works

1. You register a release (`airbuild codepush flutter release`) and install that exact build on devices.
2. You ship a patch (`airbuild codepush flutter patch` → `promote`).
3. The embedded updater checks AirBuild, downloads a binary diff, verifies its hash + signature, and applies it — active on the next app restart.

**What patches can change:** anything in Dart (`lib/`, Dart dependencies, `--dart-define` constants).
**What they can't:** native code, assets, `AndroidManifest.xml`/`Info.plist`, plugins' native parts, the Flutter engine itself — those need a new binary build + release.

### Update modes — pick one

#### Mode A: automatic updates (default, zero code)

`shorebird.yaml` ships with `auto_update: true`. On every launch, the engine's updater thread checks for patches on the **production** channel, downloads, verifies, and applies on the next launch — no Dart code needed. This is the recommended default.

You don't need `airbuild_code_push.dart` at all for this mode (you can still use it to read `currentPatch()` for diagnostics).

#### Mode B: manual updates (channels, custom UX)

Set `auto_update: false` in `shorebird.yaml`. Now the boot thread does nothing and *your* code drives everything — including which channel to check:

```yaml
# shorebird.yaml
app_id: <your-app-id>
auto_update: false
```

```dart
import 'package:airbuild/airbuild_code_push.dart';

final codePush = AirBuildCodePush();           // defaultChannel: 'production'
// or: AirBuildCodePush(defaultChannel: 'staging')
```

```dart
// Fire-and-forget — don't await during startup (initState).
codePush.checkForUpdate().then((status) async {
  if (status == UpdateStatus.outdated) {
    await codePush.update();        // downloads + installs; applies on restart
  } else if (status == UpdateStatus.restartRequired) {
    // a downloaded patch is waiting to boot — prompt the user to restart
  }
});
```

**Channels:** the channel name is sent verbatim — `checkForUpdate(channel: 'staging')` checks the staging channel, `channel: 'internal-qa'` any custom channel you promoted to. This is the only way to receive non-production patches on a device: the `channel:` key in `shorebird.yaml` is stripped at build time, and the boot thread always reports `stable` (mapped to production server-side).

#### Zero-wiring option: `AirBuildCodePushOverlay`

If you just want "check on launch + on resume + every few hours, then prompt to restart", wrap your app in the overlay instead of writing the plumbing yourself (still requires `auto_update: false`):

```dart
MaterialApp(
  builder: (context, child) => AirBuildCodePushOverlay(
    config: AirBuildCodePushConfig(
      channel: 'staging',                 // optional, default 'production'
      checkInterval: Duration(hours: 4),  // Duration.zero disables the timer
      onRestart: () => Phoenix.rebirth(context), // your restart hook
    ),
    child: child ?? const SizedBox.shrink(),
  ),
  home: const HomePage(),
)
```

The overlay checks on launch, on every resume, and on the timer; downloaded patches show a banner with **Later** / **Restart now**. Once dismissed it stays hidden until a *different* patch is staged. `showDebugBar: true` adds a live status strip ("CodePush: Downloading patch…") for dev builds, `bannerBuilder` replaces the banner entirely, and `onUpdateReady` fires once per staged patch for analytics. Reach it from anywhere via `AirBuildCodePushOverlay.maybeOf(context)` — exposes `status` (a `ValueListenable<String>`) and `checkNow()`.

#### Opting Play Store installs out of patches

If you distribute the same binary through Google Play and AirBuild and want OTA patches on AirBuild installs only:

```dart
final codePush = AirBuildCodePush(disableOnPlayStoreInstalls: true);
// or: AirBuildCodePushConfig(disableOnPlayStoreInstalls: true) on the overlay
```

On devices where the installer is `com.android.vending`, `checkForUpdate` returns `UpdateStatus.unavailable` and `update()` is a no-op; sideloaded/ADB/direct-APK installs (unknown installer) are unaffected — the check fails open. This gates only Dart-driven checks: the `auto_update` boot thread still applies patches on Play installs, so pair the flag with `auto_update: false` for a real opt-out. `installerPackageName()`/`isPlayStoreInstall()` are exported if you want the raw value.

### Reading patch state

```dart
final current = await codePush.currentPatch(); // Patch? — the patch booted now, null = base release
final next    = await codePush.nextPatch();    // Patch? — downloaded, waiting for restart
```

Useful for an "About" screen ("running patch #4") or deciding to show a restart prompt when `current != next`.

### Restart prompt example

The patch never applies mid-session — it boots on the next app restart. `showRestartBanner` gives the user a one-tap restart hook:

```dart
final status = await codePush.checkForUpdate();
if (status == UpdateStatus.outdated) {
  await codePush.update();
  if (context.mounted) {
    showRestartBanner(context, onRestart: () {
      // The SDK can't restart your app for you — use whatever your app
      // already has, e.g. the `phoenix` package: Phoenix.rebirth(context);
    });
  }
}
```

### UpdateStatus values

| Status | Meaning |
| ------ | ------- |
| `upToDate` | No newer patch on the channel |
| `outdated` | A patch is available — call `update()` to download it |
| `restartRequired` | A downloaded patch is staged — it applies on next launch |
| `unavailable` | Updater not present (debug build, unsupported platform, plain `flutter build`) — also returned when `disableOnPlayStoreInstalls` gates a Play-installed device |

### Behavior notes

- **`isAvailable`** — `false` in debug builds, tests, and builds without the updater runtime. Every method degrades gracefully (checks return `unavailable`, patch reads return `null`) — safe to call unconditionally.
- **Signing** — patch signatures are verified on-device before installing (configured automatically by the AirBuild CLI).
- **Rollback** — if a patch is rolled back server-side, the updater reverts to the base release automatically.
- **Bad patches** — a patch that fails verification/install is remembered and skipped automatically.

### Using both features together

```dart
void main() {
  AirBuild.configure(distributionKey: 'dk_xxx');   // binary-update check
  runApp(const MyApp());
}

// In a settings screen or on a timer:
Future<void> checkEverything() async {
  // 1) Is there a whole new build?
  final info = await AirBuild.checkForUpdates(currentVersion: '1.0.0');
  if (info.hasUpdate) { /* prompt to install the new build */ return; }

  // 2) Otherwise, is there a patch for this build?
  final cp = AirBuildCodePush();
  if (await cp.checkForUpdate() == UpdateStatus.outdated) {
    await cp.update();
  }
}
```

Check the *build* first: if a new binary exists, patch state is irrelevant — patches are tied to a specific release version and reset on install of a new build.
