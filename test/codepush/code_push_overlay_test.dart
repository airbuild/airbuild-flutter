import 'package:airbuild/src/codepush/airbuild_code_push.dart';
import 'package:airbuild/src/codepush/code_push_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

class _FakeUpdater extends Fake implements ShorebirdUpdater {
  UpdateStatus nextStatus = UpdateStatus.upToDate;
  int checkCalls = 0;
  int updateCalls = 0;
  Patch? nextPatchValue;

  @override
  bool get isAvailable => true;

  @override
  Future<UpdateStatus> checkForUpdate({UpdateTrack? track}) async {
    checkCalls++;
    return nextStatus;
  }

  @override
  Future<void> update({UpdateTrack? track}) async {
    updateCalls++;
  }

  @override
  Future<Patch?> readCurrentPatch() async => null;

  @override
  Future<Patch?> readNextPatch() async => nextPatchValue;
}

Widget _app({
  required AirBuildCodePush codePush,
  AirBuildCodePushConfig config = const AirBuildCodePushConfig(
    checkInterval: Duration.zero,
  ),
}) {
  return MaterialApp(
    home: AirBuildCodePushOverlay(
      config: config,
      codePush: codePush,
      child: const Scaffold(body: Text('app')),
    ),
  );
}

void main() {
  group('AirBuildCodePushOverlay', () {
    testWidgets('downloads an available patch and shows the restart banner',
        (tester) async {
      final updater = _FakeUpdater()
        ..nextStatus = UpdateStatus.outdated
        ..nextPatchValue = const Patch(number: 7);
      var readyCalls = 0;

      await tester.pumpWidget(
        _app(
          codePush: AirBuildCodePush(updater: updater),
          config: AirBuildCodePushConfig(
            checkInterval: Duration.zero,
            onUpdateReady: () => readyCalls++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(updater.checkCalls, 1);
      expect(updater.updateCalls, 1);
      expect(find.text('Restart now'), findsNothing); // no onRestart wired
      expect(find.text('Later'), findsOneWidget);
      expect(readyCalls, 1);
    });

    testWidgets('restart button appears when onRestart is provided and '
        'invokes it', (tester) async {
      final updater = _FakeUpdater()..nextStatus = UpdateStatus.outdated;
      var restarts = 0;

      await tester.pumpWidget(
        _app(
          codePush: AirBuildCodePush(updater: updater),
          config: AirBuildCodePushConfig(
            checkInterval: Duration.zero,
            onRestart: () => restarts++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Restart now'), findsOneWidget);
      await tester.tap(find.text('Restart now'));
      await tester.pumpAndSettle();
      expect(restarts, 1);
      expect(find.text('Restart now'), findsNothing);
    });

    testWidgets('Later dismisses the banner and it does not reshow for the '
        'same patch', (tester) async {
      final updater = _FakeUpdater()
        ..nextStatus = UpdateStatus.restartRequired
        ..nextPatchValue = const Patch(number: 7);

      await tester.pumpWidget(_app(codePush: AirBuildCodePush(updater: updater)));
      await tester.pumpAndSettle();
      expect(find.text('Later'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('Later'), findsNothing);

      // A fresh check still reports the same staged patch — no reshow.
      final state = tester.state<AirBuildCodePushOverlayState>(
        find.byType(AirBuildCodePushOverlay),
      );
      await state.checkNow();
      await tester.pumpAndSettle();
      expect(find.text('Later'), findsNothing);
    });

    testWidgets('banner reshown when a different patch is staged',
        (tester) async {
      final updater = _FakeUpdater()
        ..nextStatus = UpdateStatus.restartRequired
        ..nextPatchValue = const Patch(number: 7);

      await tester.pumpWidget(_app(codePush: AirBuildCodePush(updater: updater)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      updater.nextPatchValue = const Patch(number: 8);
      final state = tester.state<AirBuildCodePushOverlayState>(
        find.byType(AirBuildCodePushOverlay),
      );
      await state.checkNow();
      await tester.pumpAndSettle();
      expect(find.text('Later'), findsOneWidget);
    });

    testWidgets('checkOnResume triggers a check when the app resumes',
        (tester) async {
      final updater = _FakeUpdater();
      await tester.pumpWidget(
        _app(
          codePush: AirBuildCodePush(updater: updater),
          config: const AirBuildCodePushConfig(
            checkOnLaunch: false,
            checkInterval: Duration.zero,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(updater.checkCalls, 0);

      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(updater.checkCalls, 1);
    });

    testWidgets('checkOnLaunch: false skips the initial check',
        (tester) async {
      final updater = _FakeUpdater();
      await tester.pumpWidget(
        _app(
          codePush: AirBuildCodePush(updater: updater),
          config: const AirBuildCodePushConfig(
            checkOnLaunch: false,
            checkOnResume: false,
            checkInterval: Duration.zero,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(updater.checkCalls, 0);
    });

    testWidgets('showDebugBar renders the live status text',
        (tester) async {
      final updater = _FakeUpdater()..nextStatus = UpdateStatus.upToDate;
      await tester.pumpWidget(
        _app(
          codePush: AirBuildCodePush(updater: updater),
          config: const AirBuildCodePushConfig(
            showDebugBar: true,
            checkInterval: Duration.zero,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('CodePush:'), findsOneWidget);
      expect(find.textContaining('Up to date'), findsOneWidget);
    });

    testWidgets('Play-Store-gated codePush shows no banner and no updater '
        'calls', (tester) async {
      final updater = _FakeUpdater()..nextStatus = UpdateStatus.outdated;
      await tester.pumpWidget(
        _app(
          codePush: AirBuildCodePush(
            disableOnPlayStoreInstalls: true,
            updater: updater,
            playStoreInstallProbe: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(updater.checkCalls, 0);
      expect(find.text('Later'), findsNothing);
      final state = tester.state<AirBuildCodePushOverlayState>(
        find.byType(AirBuildCodePushOverlay),
      );
      expect(state.status.value, 'CodePush unavailable');
    });

    testWidgets('custom bannerBuilder replaces the default banner',
        (tester) async {
      final updater = _FakeUpdater()..nextStatus = UpdateStatus.outdated;
      await tester.pumpWidget(
        _app(
          codePush: AirBuildCodePush(updater: updater),
          config: AirBuildCodePushConfig(
            checkInterval: Duration.zero,
            bannerBuilder: (context, onRestart, onDismiss) => TextButton(
              onPressed: onDismiss,
              child: const Text('custom banner'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('custom banner'), findsOneWidget);
      expect(find.text('Later'), findsNothing);
      await tester.tap(find.text('custom banner'));
      await tester.pumpAndSettle();
      expect(find.text('custom banner'), findsNothing);
    });
  });
}
