import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

import 'airbuild_code_push.dart';

/// Builds the "restart to apply" banner shown by [AirBuildCodePushOverlay].
///
/// [onRestart] is the app-provided restart hook from
/// [AirBuildCodePushConfig.onRestart] — it is `null` when the app didn't
/// provide one, so builders should hide or reword the restart action in that
/// case. [onDismiss] hides the banner until a *different* patch is staged.
typedef CodePushBannerBuilder = Widget Function(
  BuildContext context,
  VoidCallback? onRestart,
  VoidCallback onDismiss,
);

/// Configuration for [AirBuildCodePushOverlay].
class AirBuildCodePushConfig {
  /// Creates overlay configuration. All fields have sensible defaults —
  /// `const AirBuildCodePushConfig()` checks `production` on launch, on
  /// resume, and every 4 hours.
  const AirBuildCodePushConfig({
    this.channel = 'production',
    this.checkOnLaunch = true,
    this.checkOnResume = true,
    this.checkInterval = const Duration(hours: 4),
    this.showDebugBar = false,
    this.disableOnPlayStoreInstalls = false,
    this.onRestart,
    this.bannerBuilder,
    this.onUpdateReady,
  });

  /// The AirBuild channel to check (`"production"`, `"staging"`, or any
  /// custom channel promoted with `airbuild codepush flutter promote
  /// --channel <name>`). Sent to the server verbatim.
  final String channel;

  /// Whether to check once when the overlay first builds. Default `true`.
  final bool checkOnLaunch;

  /// Whether to check each time the app returns to the foreground.
  /// Default `true`.
  final bool checkOnResume;

  /// How often to re-check while the app is running. Default 4 hours.
  /// Set to [Duration.zero] to disable periodic checks.
  final Duration checkInterval;

  /// Shows a thin status bar at the top of the screen with the current
  /// CodePush state (`"Checking for updates…"`, `"Patch ready"`, …).
  /// Intended for internal/dev builds. Default `false`.
  final bool showDebugBar;

  /// When `true`, patch checks and downloads are skipped entirely on
  /// devices where the app was installed from the Google Play Store —
  /// OTA updates then apply only to AirBuild-distributed/sideloaded
  /// installs. Forwarded to the internally created [AirBuildCodePush];
  /// ignored when a custom `codePush` instance is passed to the overlay.
  ///
  /// This only gates Dart-driven checks. The engine's boot-time updater
  /// (`auto_update: true` in `shorebird.yaml`) still applies patches on
  /// Play installs — set `auto_update: false` for a complete opt-out.
  final bool disableOnPlayStoreInstalls;

  /// Called when the user taps "Restart now" on the update banner, and
  /// forwarded to [bannerBuilder].
  ///
  /// The SDK cannot restart the app itself — Flutter has no process-restart
  /// API — so wire this to whatever your app already uses (e.g.
  /// `Phoenix.rebirth(context)` from the `flutter_phoenix` package, or a
  /// root-widget rebuild). When `null`, the default banner hides the
  /// restart button and only tells the user the patch applies next launch.
  final VoidCallback? onRestart;

  /// Builds the banner shown when a patch is staged. When `null`, a
  /// default [MaterialBanner]-style banner with "Later"/"Restart now"
  /// actions is used. Return `SizedBox.shrink()` to disable the banner
  /// entirely (e.g. when handling [onUpdateReady] yourself).
  final CodePushBannerBuilder? bannerBuilder;

  /// Called once per patch when a patch has been downloaded and is waiting
  /// for a restart. Runs in addition to the banner — useful for analytics
  /// or custom UX.
  final VoidCallback? onUpdateReady;
}

/// A drop-in widget that runs the whole manual CodePush lifecycle for you:
/// it checks for a patch on launch (optionally periodically and on resume),
/// downloads it, and shows a "restart to apply" banner once staged.
///
/// This is the zero-effort alternative to wiring
/// [AirBuildCodePush.checkForUpdate] + [AirBuildCodePush.update] +
/// `showRestartBanner` yourself. It only drives *Dart-initiated* checks —
/// use it with `auto_update: false` in `shorebird.yaml`, otherwise the
/// engine's boot thread already patches the `stable` (production) channel
/// and this overlay is only useful for non-production channels.
///
/// Place it inside your `MaterialApp` so it inherits `Theme`/`MediaQuery` —
/// the `builder` callback is the most reliable spot since it sits above the
/// `Navigator` and therefore covers every route:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => AirBuildCodePushOverlay(
///     config: AirBuildCodePushConfig(
///       channel: 'staging',
///       onRestart: () => Phoenix.rebirth(context),
///     ),
///     child: child ?? const SizedBox.shrink(),
///   ),
///   home: const HomePage(),
/// )
/// ```
class AirBuildCodePushOverlay extends StatefulWidget {
  /// Creates the overlay. [child] is your app content — typically the
  /// `child` handed to `MaterialApp.builder`, or your home screen.
  const AirBuildCodePushOverlay({
    super.key,
    required this.child,
    this.config = const AirBuildCodePushConfig(),
    this.codePush,
  });

  /// The app content below the overlay's banner/debug bar.
  final Widget child;

  /// Overlay behavior — see [AirBuildCodePushConfig].
  final AirBuildCodePushConfig config;

  /// The updater to drive. When `null`, the overlay creates an
  /// [AirBuildCodePush] with `config.channel` and
  /// `config.disableOnPlayStoreInstalls`. Pass your own instance to share
  /// one with the rest of your app, or to inject a mock in tests.
  final AirBuildCodePush? codePush;

  /// The nearest [AirBuildCodePushOverlay] state above [context], or `null`
  /// if the app isn't wrapped in one. Use it to read
  /// [AirBuildCodePushOverlayState.status] or to trigger
  /// [AirBuildCodePushOverlayState.checkNow] from your own UI.
  static AirBuildCodePushOverlayState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<AirBuildCodePushOverlayState>();

  @override
  State<AirBuildCodePushOverlay> createState() =>
      AirBuildCodePushOverlayState();
}

/// State for [AirBuildCodePushOverlay]. Exposed so apps can read [status]
/// and trigger [checkNow] via [AirBuildCodePushOverlay.maybeOf].
class AirBuildCodePushOverlayState extends State<AirBuildCodePushOverlay>
    with WidgetsBindingObserver {
  late final AirBuildCodePush _codePush = widget.codePush ??
      AirBuildCodePush(
        defaultChannel: widget.config.channel,
        disableOnPlayStoreInstalls: widget.config.disableOnPlayStoreInstalls,
      );

  /// A human-readable description of what CodePush is currently doing —
  /// `"idle"`, `"Checking for updates…"`, `"Downloading patch…"`,
  /// `"Patch ready — restart to apply"`, `"Up to date"`, ….
  /// Powers the debug bar; listen to it for custom status UIs.
  final ValueNotifier<String> status = ValueNotifier<String>('idle');

  Timer? _timer;
  bool _checkInFlight = false;
  bool _updatePendingRestart = false;
  bool _bannerDismissed = false;
  int? _bannerPatchNumber;
  int? _dismissedPatchNumber;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.config.checkOnLaunch) {
      // Fire-and-forget — a patch check does network I/O and must never
      // block the first frame.
      unawaited(checkNow());
    }
    final interval = widget.config.checkInterval;
    if (interval > Duration.zero) {
      _timer = Timer.periodic(interval, (_) => unawaited(checkNow()));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    status.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.config.checkOnResume) {
      unawaited(checkNow());
    }
  }

  /// Runs one check → download → prompt cycle. Safe to call any number of
  /// times — concurrent calls collapse into the in-flight check, and all
  /// failures are caught and reflected in [status] rather than thrown.
  Future<void> checkNow() async {
    if (_checkInFlight) return;
    _checkInFlight = true;
    try {
      _setStatus('Checking for updates…');
      final result =
          await _codePush.checkForUpdate(channel: widget.config.channel);
      switch (result) {
        case UpdateStatus.outdated:
          _setStatus('Downloading patch…');
          try {
            await _codePush.update(channel: widget.config.channel);
            await _markPatchReady();
          } on Exception {
            _setStatus('Patch download failed');
          }
        case UpdateStatus.restartRequired:
          await _markPatchReady();
        case UpdateStatus.upToDate:
          _setStatus('Up to date');
        case UpdateStatus.unavailable:
          _setStatus('CodePush unavailable');
      }
    } on Exception {
      _setStatus('Update check failed');
    } finally {
      _checkInFlight = false;
    }
  }

  /// A patch is downloaded and staged. Shows the banner (unless it was
  /// already dismissed for this exact patch) and fires `onUpdateReady`
  /// once per patch.
  Future<void> _markPatchReady() async {
    _setStatus('Patch ready — restart to apply');
    final patchNumber = (await _codePush.nextPatch())?.number;
    if (!mounted) return;
    if (_bannerDismissed && patchNumber == _dismissedPatchNumber) return;
    final firstForThisPatch =
        !_updatePendingRestart || patchNumber != _bannerPatchNumber;
    setState(() {
      _updatePendingRestart = true;
      _bannerPatchNumber = patchNumber;
    });
    if (firstForThisPatch) widget.config.onUpdateReady?.call();
  }

  void _dismissBanner() {
    setState(() {
      _updatePendingRestart = false;
      _bannerDismissed = true;
      _dismissedPatchNumber = _bannerPatchNumber;
    });
  }

  void _onRestart() {
    _dismissBanner();
    widget.config.onRestart?.call();
  }

  void _setStatus(String value) => status.value = value;

  @override
  Widget build(BuildContext context) {
    final overlayUi = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.config.showDebugBar) _DebugStatusBar(status: status),
        if (_updatePendingRestart) _buildBanner(context),
      ],
    );

    return Stack(
      children: [
        widget.child,
        if (widget.config.showDebugBar || _updatePendingRestart)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(child: _wrapOverlayUi(context, overlayUi)),
          ),
      ],
    );
  }

  Widget _buildBanner(BuildContext context) {
    final builder = widget.config.bannerBuilder;
    if (builder != null) {
      return builder(
        context,
        widget.config.onRestart == null ? null : _onRestart,
        _dismissBanner,
      );
    }
    return _DefaultRestartBanner(
      onRestart: widget.config.onRestart == null ? null : _onRestart,
      onDismiss: _dismissBanner,
    );
  }

  /// Guarantees the ambient widgets the banner/debug bar need, so the
  /// overlay still renders if a host places it above `MaterialApp`.
  Widget _wrapOverlayUi(BuildContext context, Widget child) {
    return Directionality(
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
  }
}

class _DebugStatusBar extends StatelessWidget {
  const _DebugStatusBar({required this.status});

  final ValueListenable<String> status;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xE6000000),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: ValueListenableBuilder<String>(
          valueListenable: status,
          builder: (context, value, _) => Text(
            'CodePush: $value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.normal,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

class _DefaultRestartBanner extends StatelessWidget {
  const _DefaultRestartBanner({
    required this.onDismiss,
    this.onRestart,
  });

  final VoidCallback onDismiss;
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: const Text(
        'An update has been downloaded and will apply on restart.',
      ),
      actions: [
        TextButton(
          onPressed: onDismiss,
          child: const Text('Later'),
        ),
        if (onRestart != null)
          FilledButton(
            onPressed: onRestart,
            child: const Text('Restart now'),
          ),
      ],
    );
  }
}
