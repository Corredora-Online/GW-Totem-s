import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/updates/release_updater.dart';
import 'app_providers.dart';
import 'cart/cart_controller.dart';
import 'checkout/checkout_controller.dart';
import 'device_config_controller.dart';

class UpdateState {
  const UpdateState({
    this.busy = false,
    this.installing = false,
    this.message =
        'Actualizaciones automáticas cada 15 minutos, sólo en reposo.',
  });
  final bool busy;
  final bool installing;
  final String message;
}

final updateProvider = StateNotifierProvider<UpdateController, UpdateState>(
  UpdateController.new,
);
final releaseUpdaterProvider = Provider<ReleaseUpdater>(
  (ref) => ReleaseUpdater(),
);
final updatePlatformProvider = Provider<String?>(
  (ref) => Platform.isAndroid
      ? 'android'
      : Platform.isWindows
      ? 'windows'
      : null,
);

class UpdateController extends StateNotifier<UpdateState> {
  UpdateController(this.ref) : super(const UpdateState());
  final Ref ref;
  static const _channel = MethodChannel('cl.gournet.kiosk/updates');
  DateTime? _nextCheck;

  bool _idle(bool Function() screenIdle) =>
      screenIdle() &&
      ref.read(deviceConfigProvider).isActivated &&
      ref.read(deviceConfigProvider).autoUpdates &&
      ref.read(cartProvider).isEmpty &&
      ref.read(checkoutProvider).stage == CheckoutStage.idle;

  Future<void> check({
    required bool Function() screenIdle,
    bool manual = false,
  }) async {
    final platform = ref.read(updatePlatformProvider);
    if (state.busy || platform == null) return;
    if (!ref.read(deviceConfigProvider).isActivated) return;
    if (!manual &&
        (!ref.read(deviceConfigProvider).autoUpdates ||
            (_nextCheck?.isAfter(DateTime.now()) ?? false))) {
      return;
    }
    _nextCheck = DateTime.now().add(const Duration(minutes: 15));
    state = const UpdateState(busy: true, message: 'Buscando actualización…');
    try {
      final updater = ref.read(releaseUpdaterProvider);
      final artifact = await updater.check(platform);
      if (artifact == null) {
        state = const UpdateState(
          message: 'No hay una versión más reciente disponible.',
        );
        return;
      }
      state = UpdateState(
        busy: true,
        message: 'Descargando ${artifact.version}…',
      );
      final file = await updater.download(artifact);
      final audit = await ref.read(paymentAuditRepositoryProvider).readAll();
      final unresolved = audit.any(
        (entry) => const {
          'processing',
          'cancellationRequested',
          'uncertain',
        }.contains(entry['status']),
      );
      if (unresolved || !_idle(screenIdle)) {
        // Reuse the verified download at the next idle opportunity.
        _nextCheck = null;
        state = UpdateState(
          message:
              '${artifact.version} lista. Se instalará en reposo y sin pagos pendientes.',
        );
        return;
      }
      // Synchronous guard: no customer can start a sale after this point.
      state = UpdateState(
        busy: true,
        installing: true,
        message: 'Instalando ${artifact.version}. El kiosko se reiniciará…',
      );
      final installed = await _channel
          .invokeMethod<bool>('installUpdate', {'path': file.path})
          .timeout(const Duration(minutes: 3));
      if (installed != true) {
        throw StateError('El instalador no confirmó la solicitud');
      }
      // Native installers restart the process. Keep touches locked until then.
      state = const UpdateState(
        busy: true,
        installing: true,
        message: 'Reiniciando el kiosko…',
      );
    } catch (error) {
      // A failed update never resets configuration, orders or the payment audit.
      state = UpdateState(message: 'No se pudo actualizar: $error');
    }
  }
}
