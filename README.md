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
  airbuild: ^0.2.0
```

```bash
flutter pub get
```

---

## Part 1 — Binary build update check

Call `AirBuild.configure()` once at startup, then `checkForUpdates()` anywhere:

```dart
import 'package:airbuild/airbuild.dart';

void main() {
  AirBuild.configure(
    distributionKey: 'dk_a1b2c3d4e5f6', // from the AirBuild dashboard
    // baseUrl: 'https://airbuild.dev', // optional override (self-hosted)
  );
  runApp(const MyApp());
}
```

```dart
// e.g. on app start or behind a "Check for Updates" button:
final info = await AirBuild.checkForUpdates(
  context: context,           // shows the built-in dialog; omit for headless check
  currentVersion: '1.0.0',    // your app's version
  appName: 'My App',          // optional — dialog title
);

if (info.hasUpdate) {
  // a newer build exists — info.installUrl / info.downloadUrl are set
}
```

The SDK handles the whole flow: checks the server → shows a dialog with version + release notes → on "Update", **Android** downloads the APK and triggers the system installer, **iOS** opens the install link in Safari (no sideloading on iOS).

The **distribution key** (`dk_xxx`) is a public identifier — safe to embed, not a secret.

**Android:** no setup needed — `INTERNET`, `REQUEST_INSTALL_PACKAGES`, and the `FileProvider` are declared by the plugin. On first install, Android may ask the user to allow installs from your app (required on API 26+).
**iOS:** no setup needed.

---

## Part 2 — CodePush (OTA Dart patches)

> **Prerequisite:** your app binary must be built by `airbuild codepush flutter release` — the AirBuild CLI compiles the OTA updater runtime into your app. A plain `flutter build` does not contain the updater. See the [Flutter CodePush guide](https://docs.airbuild.dev/guides/codepush-flutter/) for CLI setup (`airbuild codepush flutter doctor/install/init`).

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
base_url: https://airbuild.dev
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
- **Signing** — if the release build embedded `patch_public_key` (the AirBuild CLI does this automatically), the device verifies `hash_signature` before installing.
- **Rollback** — if a patch is rolled back server-side, the next check reports it in `rolled_back_patch_numbers` and the updater reverts to the base release.
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

---

## Self-hosted / staging

- Binary check: `AirBuild.configure(baseUrl: 'https://staging.airbuild.dev', ...)`
- CodePush: point `base_url` in `shorebird.yaml` at your server — the updater resolves `{base_url}/api/v1/patches/check` from the bundled config (no Dart API needed)

## Publishing

Published to [pub.dev](https://pub.dev) as `airbuild`.
