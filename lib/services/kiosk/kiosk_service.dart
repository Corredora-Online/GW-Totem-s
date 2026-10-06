import 'package:flutter/services.dart';

class KioskStatus {
  const KioskStatus({
    required this.deviceOwner,
    required this.lockTaskPermitted,
    required this.locked,
  });

  const KioskStatus.unavailable()
    : deviceOwner = false,
      lockTaskPermitted = false,
      locked = false;

  final bool deviceOwner;
  final bool lockTaskPermitted;
  final bool locked;

  factory KioskStatus.fromMap(Map<Object?, Object?> values) => KioskStatus(
    deviceOwner: values['deviceOwner'] == true,
    lockTaskPermitted: values['lockTaskPermitted'] == true,
    locked: values['locked'] == true,
  );
}

abstract final class KioskService {
  static const _channel = MethodChannel('cl.gournet.kiosk/device');

  static Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<bool>('setKioskEnabled', enabled);
    } on MissingPluginException {
      // La app también se ejecuta en plataformas sin integración Android.
    } on PlatformException {
      // El estado se volverá a sincronizar en el siguiente arranque/cambio.
    }
  }

  static Future<KioskStatus> getStatus() async {
    try {
      final values = await _channel.invokeMapMethod<Object?, Object?>(
        'getKioskStatus',
      );
      return values == null
          ? const KioskStatus.unavailable()
          : KioskStatus.fromMap(values);
    } on MissingPluginException {
      return const KioskStatus.unavailable();
    } on PlatformException {
      return const KioskStatus.unavailable();
    }
  }

  static Future<void> exitApp() async {
    await _channel.invokeMethod<bool>('exitKiosk');
  }
}
