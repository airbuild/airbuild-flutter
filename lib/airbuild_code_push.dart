/// AirBuild CodePush for Flutter — a thin wrapper around Shorebird's
/// `shorebird_code_push` package for apps distributed through an
/// AirBuild-hosted (or self-hosted) control plane.
///
/// This is a separate library from `package:airbuild/airbuild.dart` (the
/// binary-distribution SDK) because it pulls in the `shorebird_code_push`
/// dependency, which requires the Shorebird updater runtime to be compiled
/// into your app (via `shorebird release`/`shorebird patch`, not a plain
/// `flutter build`). Only import this if you're using AirBuild CodePush.
///
/// Usage:
///
/// ```dart
/// import 'package:airbuild/airbuild_code_push.dart';
///
/// final codePush = AirBuildCodePush();
///
/// // Check for a patch (don't await this during app startup — see the
/// // shorebird_code_push docs on why).
/// codePush.checkForUpdate().then((status) {
///   if (status == UpdateStatus.outdated) {
///     codePush.update();
///   }
/// });
/// ```
///
/// For a zero-effort integration that handles check → download →
/// restart-prompt itself (with `auto_update: false` in `shorebird.yaml`),
/// wrap your app in [AirBuildCodePushOverlay]:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => AirBuildCodePushOverlay(
///     config: AirBuildCodePushConfig(onRestart: () => restartMyApp()),
///     child: child ?? const SizedBox.shrink(),
///   ),
///   home: const HomePage(),
/// );
/// ```
///
/// For this to talk to your AirBuild server instead of Shorebird's cloud,
/// your `shorebird.yaml` must point `base_url` at it:
///
/// ```yaml
/// # shorebird.yaml
/// app_id: <your-shorebird-app-id>
/// base_url: https://airbuild.dev
/// ```
///
/// See `docs/guides/flutter-codepush.md` for the full setup guide,
/// including how releases/patches are created via the `airbuild` CLI.
library airbuild_code_push;

export 'package:shorebird_code_push/shorebird_code_push.dart'
    show
        Patch,
        ReadPatchException,
        UpdateException,
        UpdateFailureReason,
        UpdateStatus,
        UpdateTrack;

export 'src/codepush/airbuild_code_push.dart';
export 'src/codepush/code_push_overlay.dart';
export 'src/codepush/restart_banner.dart';
export 'src/install_source.dart'
    show installerPackageName, isPlayStoreInstall, playStorePackageName;
