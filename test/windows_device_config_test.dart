import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/domain/models/device_config.dart';

void main() {
  test('persiste puerto COM e impresora sin mezclar secretos', () {
    const config = DeviceConfig(
      apiKey: 'secret',
      adminPinHash: 'pin',
      windowsGetnetPort: 'COM5',
      windowsPrinterName: 'POS-80',
    );
    final serialized = config.toJson();
    expect(serialized['apiKey'], isNull);
    expect(serialized['adminPinHash'], isNull);
    final restored = DeviceConfig.fromJson(
      serialized,
      apiKey: 'secure-secret',
      adminPinHash: 'secure-pin',
    );
    expect(restored.windowsGetnetPort, 'COM5');
    expect(restored.windowsPrinterName, 'POS-80');
    expect(restored.apiKey, 'secure-secret');
  });
}
