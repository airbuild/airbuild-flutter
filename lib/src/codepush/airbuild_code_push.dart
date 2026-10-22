import 'package:flutter/foundation.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

import '../install_source.dart';

/// A thin, AirBuild-branded wrapper around Shorebird's [ShorebirdUpdater].
///
/// This does **not** talk to AirBuild's server directly — the actual patch
/// check/download happens in Shorebird's updater runtime, which is compiled
/// into your app and configured via `shorebird.yaml`'s `base_url` field to
/// point at your AirBuild server instead of Shorebird's own cloud:
///
/// ```yaml
/// # shorebird.yaml
/// app_id: <your-shorebird-app-id>
/// base_url: https://airbuild.dev
/// ```
///
/// What this class adds on top of [ShorebirdUpdater] is:
/// - Mapping AirBuild's channel names (e.g. `"production"`, `"staging"`)
///   onto Shorebird's [UpdateTrack] concept, so app code can talk about
///   "channels" consistently with the AirBuild dashboard/CLI.
///
/// This is a different feature from `AirBuild.checkForUpdates()` in
/// `package:airbuild/airbuild.dart` — that checks whether a *new binary
/// build* (APK/IPA) is available on AirBuild and prompts the user to
/// install it. This class manages *patches* applied on top of the build
/// that's already installed. Apps can use either, both, or neither.
///
/// Update modes (set `auto_update` in `shorebird.yaml`):
/// - `auto_update: true` (default): the engine's boot thread automatically
///   checks the `stable` channel on every launch and installs production
///   patches in the background — no code needed, but channels are not
///   selectable and the boot check ignores this class.
/// - `auto_update: false`: nothing happens automatically; drive updates
///   yourself via [checkForUpdate]/[update], which also enables per-device
///   channel selection (e.g. `AirBuildCodePush(defaultChannel: 'staging')`).
///
/// If the updater isn't available (e.g. running a debug build, or a
/// platform Shorebird doesn't support), every method degrades gracefully
/// instead of throwing — check [isAvailable] if you need to know why no
/// update was found.
class AirBuildCodePush {
  /// Creates a wrapper around Shorebird's updater.
  ///
  /// [defaultChannel] is used by [checkForUpdate] and [update] when no
  /// channel is passed explicitly. Defaults to `"production"`, matching
  /// the default channel used by `airbuild codepush flutter promote`.
  ///
  /// [disableOnPlayStoreInstalls] disables Dart-driven patch checks and
  /// downloads when the running build was installed from the Google Play
  /// Store (`com.android.vending`) — useful if you want OTA patches for
  /// AirBuild-distributed/sideloaded installs only. [checkForUpdate]
  /// returns [UpdateStatus.unavailable] and [update] becomes a no-op on
  /// Play-installed devices; [currentPatch]/[nextPatch] still report patch
  /// state. The check fails open: if the install source can't be
  /// determined (sideloads, ADB, older APIs), updates stay enabled.
  ///
  /// Note: this flag only gates checks made through Dart. The engine's
  /// boot-time updater thread (`auto_update: true` in `shorebird.yaml`)
  /// runs before Dart starts and is unaffected — combine this flag with
  /// `auto_update: false` for a complete opt-out.
  AirBuildCodePush({
    String defaultChannel = 'production',
    bool disableOnPlayStoreInstalls = false,
    @visibleForTesting ShorebirdUpdater? updater,
    @visibleForTesting Future<bool> Function()? playStoreInstallProbe,
  })  : _defaultChannel = defaultChannel,
        _disableOnPlayStoreInstalls = disableOnPlayStoreInstalls,
        _updater = updater ?? ShorebirdUpdater(),
        _playStoreInstallProbe = playStoreInstallProbe ?? isPlayStoreInstall;

  final ShorebirdUpdater _updater;
  final String _defaultChannel;
  final bool _disableOnPlayStoreInstalls;
  final Future<bool> Function() _playStoreInstallProbe;

  /// Whether the Shorebird updater is available on this build/platform.
  ///
  /// This is `false` for debug builds, and for platforms/build modes the
  /// Shorebird updater runtime doesn't support. When `false`, every other
  /// method in this class is effectively a no-op.
  bool get isAvailable => _updater.isAvailable;

  /// Maps an AirBuild channel name to Shorebird's [UpdateTrack].
  ///
  /// [UpdateTrack] is a free-form string — the name is sent verbatim as the
  /// `channel` field of the patch-check request, and the AirBuild server
  /// resolves it against your app's channels (`production`, `staging`, or
  /// any custom name used with `airbuild codepush flutter promote
  /// --channel <name>`). Names are passed through unchanged; the server's
  /// built-in `stable` → `production` fallback only exists for the
  /// boot-time auto-updater, which always reports `stable`.
  ///
  /// Note: this only affects checks and downloads triggered through this
  /// class. The engine's automatic update thread (enabled when
  /// `auto_update: true` in `shorebird.yaml`) always checks `stable`.
  /// To control channels from Dart, set `auto_update: false` and drive
  /// updates manually via [checkForUpdate]/[update].
  static UpdateTrack trackForChannel(String channel) => UpdateTrack(channel);

  /// Returns the currently installed patch, or `null` if the app is
  /// running the release build with no patch applied (or the updater is
  /// unavailable).
  Future<Patch?> currentPatch() {
    if (!isAvailable) return Future.value(null);
    return _updater.readCurrentPatch();
  }

  /// Returns the most recently downloaded patch (which may not be applied
  /// yet — see [UpdateStatus.restartRequired]), or `null` if none has been
  /// downloaded.
  Future<Patch?> nextPatch() {
    if (!isAvailable) return Future.value(null);
    return _updater.readNextPatch();
  }

  /// Checks AirBuild (via the Shorebird updater) for a new patch on
  /// [channel] (defaults to the channel this instance was configured
  /// with). Returns [UpdateStatus.unavailable] if the updater isn't
  /// available rather than throwing.
  ///
  /// This makes a network call — don't await it during app startup (e.g.
  /// in `initState`); call it fire-and-forget with `.then()` instead, per
  /// Shorebird's own guidance.
  Future<UpdateStatus> checkForUpdate({String? channel}) async {
    if (!isAvailable || await _updatesDisabled()) {
      return UpdateStatus.unavailable;
    }
    return _updater.checkForUpdate(
      track: trackForChannel(channel ?? _defaultChannel),
    );
  }

  /// Downloads and installs the latest patch on [channel] (defaults to the
  /// channel this instance was configured with). The patch takes effect on
  /// the next full app restart — this call does not restart the app for
  /// you.
  ///
  /// Call [checkForUpdate] first and only call this when the status is
  /// [UpdateStatus.outdated], matching Shorebird's own recommended flow.
  Future<void> update({String? channel}) async {
    if (!isAvailable || await _updatesDisabled()) return;
    return _updater.update(
      track: trackForChannel(channel ?? _defaultChannel),
    );
  }

  /// Whether patch checks/downloads are disabled for this device by the
  /// `disableOnPlayStoreInstalls` flag. Fails open — an undeterminable
  /// install source never disables updates.
  Future<bool> _updatesDisabled() async {
    if (!_disableOnPlayStoreInstalls) return false;
    try {
      return await _playStoreInstallProbe();
    } on Exception {
      return false;
    }
  }
}
