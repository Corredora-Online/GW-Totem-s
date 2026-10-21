import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/app.dart';
import 'package:gournet_kiosk/data/mock/mock_config_repository.dart';
import 'package:gournet_kiosk/domain/models/device_config.dart';
import 'package:gournet_kiosk/state/device_config_controller.dart';

class _FailingRepository extends MockConfigRepository {
  @override
  Future<void> save(DeviceConfig config) async {
    throw StateError('Storage unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cl.gournet.kiosk/device');
  late List<bool> nativeChanges;
  var failNextChange = false;

  setUp(() {
    nativeChanges = [];
    failNextChange = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'setAutoStartEnabled');
          final enabled = call.arguments as bool;
          nativeChanges.add(enabled);
          if (failNextChange) {
            failNextChange = false;
            throw PlatformException(code: 'AUTO_START_FAILED');
          }
          return enabled;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('inicio automático activo en instalaciones nuevas y configuraciones antiguas', () {
    expect(const DeviceConfig().autoStart, isTrue);
    final migrated = DeviceConfig.fromJson(
      const {},
      apiKey: '',
      adminPinHash: '',
    );
    expect(migrated.autoStart, isTrue);
  });

  test('desactivar se conserva en JSON y al editar otros ajustes', () {
    const disabled = DeviceConfig(autoStart: false);
    final restored = DeviceConfig.fromJson(
      disabled.toJson(),
      apiKey: '',
      adminPinHash: '',
    );
    expect(restored.autoStart, isFalse);
    expect(restored.copyWith(restaurantName: 'Local').autoStart, isFalse);
  });

  test(
    'guardar aplica el cambio al sistema y persiste la preferencia',
    () async {
      final repository = MockConfigRepository();
      final controller = DeviceConfigController(
        repository,
        const DeviceConfig(),
      );
      addTearDown(controller.dispose);

      await controller.replace(controller.state.copyWith(autoStart: false));
      expect(nativeChanges, [false]);
      expect(repository.value.autoStart, isFalse);

      await controller.replace(
        controller.state.copyWith(restaurantName: 'Local'),
      );
      expect(nativeChanges, [false]);
      expect(repository.value.autoStart, isFalse);

      await controller.replace(controller.state.copyWith(autoStart: true));
      expect(nativeChanges, [false, true]);
      expect(repository.value.autoStart, isTrue);
    },
  );

  test(
    'un fallo del sistema impide guardar un estado que no se pudo aplicar',
    () async {
      final repository = MockConfigRepository();
      final controller = DeviceConfigController(
        repository,
        const DeviceConfig(),
      );
      addTearDown(controller.dispose);
      failNextChange = true;

      await expectLater(
        controller.replace(controller.state.copyWith(autoStart: false)),
        throwsA(isA<PlatformException>()),
      );

      expect(controller.state.autoStart, isTrue);
      expect(repository.value.autoStart, isTrue);
      expect(nativeChanges, [false, true]);
    },
  );

  test(
    'un fallo de almacenamiento restaura el registro de inicio anterior',
    () async {
      final controller = DeviceConfigController(
        _FailingRepository(),
        const DeviceConfig(),
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.replace(controller.state.copyWith(autoStart: false)),
        throwsStateError,
      );

      expect(controller.state.autoStart, isTrue);
      expect(nativeChanges, [false, true]);
    },
  );

  test(
    'restablecer de fábrica vuelve a activar el inicio automático',
    () async {
      const disabled = DeviceConfig(autoStart: false);
      final repository = MockConfigRepository()..value = disabled;
      final controller = DeviceConfigController(repository, disabled);
      addTearDown(controller.dispose);

      await controller.factoryReset();

      expect(controller.state.autoStart, isTrue);
      expect(repository.value.autoStart, isTrue);
      expect(nativeChanges, [true]);
    },
  );

  testWidgets('al abrir la app se reaplica el inicio desactivado guardado', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setAutoStartEnabled') {
            nativeChanges.add(call.arguments as bool);
          }
          return call.arguments;
        });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialDeviceConfigProvider.overrideWithValue(
            const DeviceConfig(autoStart: false),
          ),
        ],
        child: const GournetKioskApp(),
      ),
    );
    await tester.pump();

    expect(nativeChanges, [false]);
    expect(find.text('Activa tu tótem'), findsOneWidget);
  });
}
