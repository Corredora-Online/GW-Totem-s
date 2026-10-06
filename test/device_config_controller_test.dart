import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/data/mock/mock_config_repository.dart';
import 'package:gournet_kiosk/domain/models/device_config.dart';
import 'package:gournet_kiosk/state/device_config_controller.dart';

void main() {
  test('guarda la ubicación configurada del terminal de pago', () {
    const original = DeviceConfig(
      paymentTerminalSide: PaymentTerminalSide.left,
      paymentTerminalVerticalPosition: PaymentTerminalVerticalPosition.bottom,
    );

    final restored = DeviceConfig.fromJson(
      original.toJson(),
      apiKey: '',
      adminPinHash: '',
    );

    expect(restored.paymentTerminalSide, PaymentTerminalSide.left);
    expect(
      restored.paymentTerminalVerticalPosition,
      PaymentTerminalVerticalPosition.bottom,
    );
  });

  test('reserva correlativos persistentes comenzando en cero', () async {
    final repository = MockConfigRepository();
    final controller = DeviceConfigController(repository, const DeviceConfig());

    expect(await controller.reserveOrderNumber(), 0);
    expect(await controller.reserveOrderNumber(), 1);
    expect(controller.state.nextOrderNumber, 2);
    expect(repository.value.nextOrderNumber, 2);
  });

  test(
    'restablecer de fábrica elimina la activación del controlador',
    () async {
      final repository = MockConfigRepository();
      const activated = DeviceConfig(
        apiKey: 'test-api-key',
        branchId: '24',
        branchCode: '5QQTw5u1K8ed',
        branchName: 'LOCAL',
      );
      repository.value = activated;
      final controller = DeviceConfigController(repository, activated);

      await controller.factoryReset();

      expect(controller.state.isActivated, isFalse);
      expect(controller.state.apiKey, isEmpty);
      expect(controller.state.branchCode, isEmpty);
      expect(repository.value.isActivated, isFalse);
    },
  );
}
