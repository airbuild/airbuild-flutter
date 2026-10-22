import 'package:flutter/material.dart';

/// Called when the tester taps "Restart now" on [showRestartBanner]. The
/// SDK deliberately doesn't restart the app itself — Flutter has no
/// built-in "restart the process" API, and the right mechanism varies by
/// app (a `Restart.restartApp()`-style package, popping back to a root
/// widget and rebuilding it, or simply asking the user to close and reopen
/// manually). Provide whichever of those your app already uses.
typedef OnRestartCallback = void Function();

/// Shows a [MaterialBanner] telling the tester a patch has been downloaded
/// and will apply on the next restart, with a "Restart now" action.
///
/// Call this after [AirBuildCodePush.update] completes (i.e. once
/// [AirBuildCodePush.checkForUpdate] has returned
/// `UpdateStatus.restartRequired`, or right after a successful `update()`
/// call) — not before, since the patch isn't downloaded yet.
///
/// ```dart
/// final status = await codePush.checkForUpdate();
/// if (status == UpdateStatus.outdated) {
///   await codePush.update();
///   if (context.mounted) {
///     showRestartBanner(context, onRestart: () {
///       // e.g. Phoenix.rebirth(context), or your own app-restart logic.
///     });
///   }
/// }
/// ```
void showRestartBanner(
  BuildContext context, {
  required OnRestartCallback onRestart,
  String message = 'An update has been downloaded and will apply on restart.',
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentMaterialBanner()
    ..showMaterialBanner(
      MaterialBanner(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            },
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              onRestart();
            },
            child: const Text('Restart now'),
          ),
        ],
      ),
    );
}
