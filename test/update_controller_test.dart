import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/data/local/payment_audit_repository.dart';
import 'package:gournet_kiosk/domain/models/device_config.dart';
import 'package:gournet_kiosk/services/updates/release_updater.dart';
import 'package:gournet_kiosk/state/app_providers.dart';
import 'package:gournet_kiosk/state/device_config_controller.dart';
import 'package:gournet_kiosk/state/update_controller.dart';

class FakeUpdater extends ReleaseUpdater {
  int checks = 0;
  Completer<void>? downloading;
  @override
  Future<ReleaseArtifact?> check(String platform) async {
    checks++;
    return const ReleaseArtifact('1.0.1', 1000001, 'test.apk', '', 1);
  }

  @override
  Future<File> download(ReleaseArtifact artifact) async {
    await downloading?.future;
    return File('/unused/test.apk');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late PaymentAuditRepository audit;
  late FakeUpdater updater;
  late ProviderContainer container;
  var installs = 0;
  var failInstall = false;
  const channel = MethodChannel('cl.gournet.kiosk/updates');
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gournet-update-controller');
    audit = PaymentAuditRepository(storageDirectory: () async => dir);
    updater = FakeUpdater();
    installs = 0;
    failInstall = false;
    container = ProviderContainer(
      overrides: [
        initialDeviceConfigProvider.overrideWithValue(
          const DeviceConfig(apiKey: 'test', branchCode: 'test-tus'),
        ),
        paymentAuditRepositoryProvider.overrideWithValue(audit),
        releaseUpdaterProvider.overrideWithValue(updater),
        updatePlatformProvider.overrideWithValue('android'),
      ],
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          installs++;
          if (failInstall) throw PlatformException(code: 'TEST_FAILURE');
          return true;
        });
  });
  tearDown(() async {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await dir.delete(recursive: true);
  });
  test('manual check outside idle downloads but never installs', () async {
    await container
        .read(updateProvider.notifier)
        .check(screenIdle: () => false, manual: true);
    expect(installs, 0);
    expect(container.read(updateProvider).installing, false);
  });
  test('an unresolved payment blocks installation', () async {
    await audit.begin(transactionId: 'pending', orderNumber: 1, amount: 500);
    await container.read(updateProvider.notifier).check(screenIdle: () => true);
    expect(installs, 0);
  });
  test(
    'rechecks idle after download and does not interrupt customer',
    () async {
      updater.downloading = Completer<void>();
      var idle = true;
      final checking = container
          .read(updateProvider.notifier)
          .check(screenIdle: () => idle);
      idle = false;
      updater.downloading!.complete();
      await checking;
      expect(installs, 0);
    },
  );
  test(
    'only one installation starts and touches remain locked for restart',
    () async {
      await container
          .read(updateProvider.notifier)
          .check(screenIdle: () => true);
      await container
          .read(updateProvider.notifier)
          .check(screenIdle: () => true, manual: true);
      expect(installs, 1);
      expect(container.read(updateProvider).installing, true);
    },
  );
  test('installation failure unlocks app and backs off retries', () async {
    failInstall = true;
    await container.read(updateProvider.notifier).check(screenIdle: () => true);
    expect(container.read(updateProvider).installing, false);
    await container.read(updateProvider.notifier).check(screenIdle: () => true);
    expect(installs, 1);
    expect(updater.checks, 1);
  });
}
