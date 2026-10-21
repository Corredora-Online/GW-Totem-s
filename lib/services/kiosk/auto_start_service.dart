import 'package:flutter/services.dart';

/// Synchronizes the persisted preference with the operating system.
abstract final class AutoStartService {
  static const _channel = MethodChannel('cl.gournet.kiosk/device');

  static Future<void> setEnabled(bool enabled) async {
    try {
      final applied = await _channel.invokeMethod<bool>(
        'setAutoStartEnabled',
        enabled,
      );
      if (applied != enabled) {
        throw PlatformException(
          code: 'AUTO_START_FAILED',
          message: 'El sistema no confirmó el cambio de inicio automático.',
        );
      }
    } on MissingPluginException {
      // Other platforms and Flutter tests have no native startup integration.
    }
  }
}
