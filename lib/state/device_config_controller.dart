import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/admin_pin.dart';
import '../data/local/local_config_repository.dart';
import '../domain/models/device_config.dart';
import '../domain/repositories/config_repository.dart';

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => LocalConfigRepository(),
);

final initialDeviceConfigProvider = Provider<DeviceConfig>(
  (ref) => DeviceConfig(adminPinHash: AdminPin.hash(AdminPin.defaultPin)),
);

class DeviceConfigController extends StateNotifier<DeviceConfig> {
  DeviceConfigController(this._repository, DeviceConfig initial)
    : super(initial);

  final ConfigRepository _repository;

  Future<void> replace(DeviceConfig value) async {
    final previous = state;
    state = value;
    try {
      await _repository.save(value);
    } catch (_) {
      state = previous;
      rethrow;
    }
  }

  void setOperatingMode(OperatingMode value) =>
      unawaited(replace(state.copyWith(operatingMode: value)));
  void setOnline(bool value) =>
      unawaited(replace(state.copyWith(online: value)));
  void setPaymentOutcome(MockPaymentOutcome value) =>
      unawaited(replace(state.copyWith(paymentOutcome: value)));
  void setPrinterState(MockPrinterState value) =>
      unawaited(replace(state.copyWith(printerState: value)));
  void setDteOutcome(MockDteOutcome value) =>
      unawaited(replace(state.copyWith(dteOutcome: value)));

  Future<int> reserveOrderNumber() async {
    final number = state.nextOrderNumber;
    await replace(state.copyWith(nextOrderNumber: number + 1));
    return number;
  }

  void reset() {
    final defaults = DeviceConfig(
      apiKey: state.apiKey,
      adminPinHash: state.adminPinHash,
      nextOrderNumber: state.nextOrderNumber,
    );
    unawaited(replace(defaults));
  }

  Future<void> factoryReset() async {
    final previous = state;
    state = LocalConfigRepository.newInstallationConfig(
      pinHash: AdminPin.hash(AdminPin.defaultPin),
    );
    try {
      await _repository.factoryReset();
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}

final deviceConfigProvider =
    StateNotifierProvider<DeviceConfigController, DeviceConfig>((ref) {
      return DeviceConfigController(
        ref.watch(configRepositoryProvider),
        ref.watch(initialDeviceConfigProvider),
      );
    });
