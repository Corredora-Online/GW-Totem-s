import '../models/device_config.dart';

abstract interface class ConfigRepository {
  Future<DeviceConfig> load();
  Future<void> save(DeviceConfig config);
  Future<void> factoryReset();
}
