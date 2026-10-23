import 'package:flutter/material.dart';
import 'package:airbuild/airbuild.dart';
// Only needed if you use AirBuild CodePush (OTA Dart patches) — see the
// "CodePush (OTA Dart patches)" section of the README before importing
// this in a real app, since it requires a Shorebird-built binary
// (`shorebird release`/`shorebird patch`), not a plain `flutter build`.
import 'package:airbuild/airbuild_code_push.dart';

void main() {
  // Configure the SDK with your app's distribution key.
  // Get this key from the AirBuild dashboard (App Settings page).
  AirBuild.configure(
    distributionKey: 'dkYOUR_DISTRIBUTION_KEY_HERE',
    // baseUrl: 'https://airbuild.dev', // optional, defaults to airbuild.dev
  );
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AirBuild SDK Example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Wraps Shorebird's updater; safe to construct even if this build wasn't
  // produced by `shorebird release`/`shorebird patch` — isAvailable will
  // just be false, and every method becomes a no-op instead of throwing.
  final _codePush = AirBuildCodePush();

  Patch? _currentPatch;
  String _codePushStatus = 'Not checked yet';

  /// APK download progress (0–1) while a custom update install is running,
  /// or null when idle. Fed by `AirBuild.installUpdate`'s `onProgress`.
  double? _downloadProgress;

  @override
  void initState() {
    super.initState();
    // Don't await network calls like checkForUpdate/readCurrentPatch in
    // initState — use .then() so the UI isn't blocked on the splash screen.
    _codePush.currentPatch().then((patch) {
      if (mounted) setState(() => _currentPatch = patch);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AirBuild SDK Example')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // --- Binary distribution (new app version) ---
              const Text(
                'Tap the button to check for a new build.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _checkForUpdates(context),
                icon: const Icon(Icons.system_update),
                label: const Text('Check for Updates'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _checkForUpdatesSilent(context),
                icon: const Icon(Icons.tune),
                label: const Text('Check silently (custom dialog)'),
              ),
              if (_downloadProgress != null) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _downloadProgress),
                const SizedBox(height: 4),
                Text(
                  'Downloading… ${((_downloadProgress ?? 0) * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],

              const SizedBox(height: 48),
              const Divider(),
              const SizedBox(height: 24),

              // --- CodePush (OTA Dart patch) ---
              Text(
                _currentPatch != null
                    ? 'Current patch: #${_currentPatch!.number}'
                    : 'No patch installed (running the base release)',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(_codePushStatus, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => _checkForCodePushUpdate(context),
                icon: const Icon(Icons.bolt),
                label: const Text('Check for CodePush patch'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The default flow: pass `context` and the SDK shows its built-in
  /// update dialog, runs the install flow, and reports analytics events.
  Future<void> _checkForUpdates(BuildContext context) async {
    try {
      final result = await AirBuild.checkForUpdates(
        context: context,
        currentVersion: '1.0.0',
        appName: 'Example App',
      );
      if (!result.hasUpdate && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are on the latest version.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking for updates: $e')),
        );
      }
    }
  }

  /// The headless flow: omit `context` so no dialog is shown — you get an
  /// [UpdateInfo] back and decide what to do with it. This is how you build
  /// fully custom update UIs (bottom sheets, banners, forced-update gates…).
  ///
  /// Here we still reuse the SDK's [showUpdateDialog] but with our own
  /// callbacks — useful when you want the SDK's dialog UI but need to hook
  /// the Update/Later actions (analytics, forced updates, custom install).
  Future<void> _checkForUpdatesSilent(BuildContext context) async {
    try {
      // No `context` — nothing is shown; we inspect the result ourselves.
      final info = await AirBuild.checkForUpdates(currentVersion: '1.0.0');

      if (!context.mounted) return;

      if (!info.hasUpdate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are on the latest version.')),
        );
        return;
      }

      // Every field on UpdateInfo is available for custom UIs:
      //   info.latestVersion, info.latestBuildNumber, info.releaseNotes,
      //   info.fileSizeBytes / info.fileSizeDisplay, info.iconUrl,
      //   info.downloadUrl (Android APK), info.installUrl (iOS),
      //   info.minOsVersion, info.isPasswordProtected, info.createdAt.
      final accepted = await showUpdateDialog(
        context,
        update: info,
        appName: 'Example App',
        onUpdate: () async {
          // AirBuild.installUpdate runs the same in-app install the
          // default dialog uses — on Android it downloads the APK inside
          // the app and launches the system installer (no browser), on
          // iOS it opens the install URL in Safari. `onProgress` reports
          // download progress so a custom UI can show a bar.
          try {
            await AirBuild.installUpdate(
              info,
              onProgress: (received, total) {
                if (mounted && total > 0) {
                  setState(() => _downloadProgress = received / total);
                }
              },
            );
          } finally {
            if (mounted) setState(() => _downloadProgress = null);
          }
        },
        onLater: () {
          // Optional hook — runs when the user taps "Later". The dialog
          // still dismisses itself afterwards.
        },
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accepted == true
                  ? 'Update accepted'
                  : 'Update declined or dismissed',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking for updates: $e')),
        );
      }
    }
  }

  Future<void> _checkForCodePushUpdate(BuildContext context) async {
    if (!_codePush.isAvailable) {
      setState(() => _codePushStatus =
          'CodePush unavailable (this build wasn\'t produced by shorebird release/patch)');
      return;
    }

    setState(() => _codePushStatus = 'Checking...');
    final status =
        await _codePush.checkForUpdate(); // default "production" channel

    switch (status) {
      case UpdateStatus.upToDate:
        setState(() => _codePushStatus = 'Up to date.');
      case UpdateStatus.restartRequired:
        setState(() => _codePushStatus = 'Patch already downloaded.');
        if (context.mounted) {
          showRestartBanner(context, onRestart: _restartApp);
        }
      case UpdateStatus.outdated:
        setState(() => _codePushStatus = 'Downloading patch...');
        await _codePush.update();
        setState(() => _codePushStatus = 'Patch downloaded.');
        if (context.mounted) {
          showRestartBanner(context, onRestart: _restartApp);
        }
      case UpdateStatus.unavailable:
        setState(() => _codePushStatus = 'CodePush unavailable.');
    }
  }

  void _restartApp() {
    // The SDK deliberately doesn't restart your app for you — plug in
    // whatever mechanism your app already uses, e.g. the `flutter_phoenix`
    // package's `Phoenix.rebirth(context)`. This example just re-reads the
    // current patch to reflect that it's now active (a real restart is
    // required for the patched Dart code to actually take effect).
    _codePush.currentPatch().then((patch) {
      if (mounted) setState(() => _currentPatch = patch);
    });
  }
}
