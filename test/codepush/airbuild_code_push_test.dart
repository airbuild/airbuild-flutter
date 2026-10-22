import 'package:airbuild/src/codepush/airbuild_code_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

class _FakeUpdater extends Fake implements ShorebirdUpdater {
  bool available = true;
  UpdateStatus nextStatus = UpdateStatus.upToDate;
  int checkCalls = 0;
  int updateCalls = 0;
  UpdateTrack? lastTrack;
  Patch? currentPatchValue;
  Patch? nextPatchValue;

  @override
  bool get isAvailable => available;

  @override
  Future<UpdateStatus> checkForUpdate({UpdateTrack? track}) async {
    checkCalls++;
    lastTrack = track;
    return nextStatus;
  }

  @override
  Future<void> update({UpdateTrack? track}) async {
    updateCalls++;
    lastTrack = track;
  }

  @override
  Future<Patch?> readCurrentPatch() async => currentPatchValue;

  @override
  Future<Patch?> readNextPatch() async => nextPatchValue;
}

void main() {
  group('AirBuildCodePush.trackForChannel', () {
    test('passes channel names through verbatim — the server resolves them',
        () {
      expect(
          AirBuildCodePush.trackForChannel('production').value, 'production');
      expect(AirBuildCodePush.trackForChannel('staging').value, 'staging');
      expect(
          AirBuildCodePush.trackForChannel('internal-qa').value, 'internal-qa');
    });
  });

  group('AirBuildCodePush construction', () {
    test('isAvailable does not throw when the updater runtime is absent', () {
      // Running under `flutter test` (no Shorebird-embedded binary), the
      // updater should report unavailable rather than throwing, so apps
      // can safely construct AirBuildCodePush() unconditionally.
      final codePush = AirBuildCodePush();
      expect(codePush.isAvailable, isFalse);
    });

    test('checkForUpdate resolves to unavailable instead of throwing',
        () async {
      final codePush = AirBuildCodePush();
      final status = await codePush.checkForUpdate();
      expect(status, UpdateStatus.unavailable);
    });

    test('currentPatch resolves to null instead of throwing', () async {
      final codePush = AirBuildCodePush();
      expect(await codePush.currentPatch(), isNull);
    });
  });

  group('AirBuildCodePush.disableOnPlayStoreInstalls', () {
    test(
        'checkForUpdate returns unavailable on Play installs without '
        'touching the updater', () async {
      final updater = _FakeUpdater()..nextStatus = UpdateStatus.outdated;
      final codePush = AirBuildCodePush(
        disableOnPlayStoreInstalls: true,
        updater: updater,
        playStoreInstallProbe: () async => true,
      );

      expect(await codePush.checkForUpdate(), UpdateStatus.unavailable);
      expect(updater.checkCalls, 0);
    });

    test('update is a no-op on Play installs', () async {
      final updater = _FakeUpdater();
      final codePush = AirBuildCodePush(
        disableOnPlayStoreInstalls: true,
        updater: updater,
        playStoreInstallProbe: () async => true,
      );

      await codePush.update();
      expect(updater.updateCalls, 0);
    });

    test('non-Play installs check normally', () async {
      final updater = _FakeUpdater()..nextStatus = UpdateStatus.outdated;
      final codePush = AirBuildCodePush(
        disableOnPlayStoreInstalls: true,
        updater: updater,
        playStoreInstallProbe: () async => false,
      );

      expect(await codePush.checkForUpdate(), UpdateStatus.outdated);
      expect(updater.checkCalls, 1);
    });

    test('flag off never consults the probe', () async {
      final updater = _FakeUpdater();
      var probeCalls = 0;
      final codePush = AirBuildCodePush(
        updater: updater,
        playStoreInstallProbe: () async {
          probeCalls++;
          return true;
        },
      );

      await codePush.checkForUpdate();
      await codePush.update();
      expect(probeCalls, 0);
      expect(updater.checkCalls, 1);
      expect(updater.updateCalls, 1);
    });

    test('a failing probe fails open — updates stay enabled', () async {
      final updater = _FakeUpdater()..nextStatus = UpdateStatus.upToDate;
      final codePush = AirBuildCodePush(
        disableOnPlayStoreInstalls: true,
        updater: updater,
        playStoreInstallProbe: () async => throw Exception('lookup failed'),
      );

      expect(await codePush.checkForUpdate(), UpdateStatus.upToDate);
      expect(updater.checkCalls, 1);
    });

    test('patch reads stay available on Play installs for diagnostics',
        () async {
      final updater = _FakeUpdater()
        ..currentPatchValue = const Patch(number: 3);
      final codePush = AirBuildCodePush(
        disableOnPlayStoreInstalls: true,
        updater: updater,
        playStoreInstallProbe: () async => true,
      );

      expect((await codePush.currentPatch())?.number, 3);
    });
  });
}
