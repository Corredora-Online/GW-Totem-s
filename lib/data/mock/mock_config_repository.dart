import '../../domain/models/device_config.dart';
import '../../domain/repositories/config_repository.dart';

class MockConfigRepository implements ConfigRepository {
  DeviceConfig value = const DeviceConfig();

  @override
  Future<DeviceConfig> load() async => value;

  @override
  Future<void> save(DeviceConfig config) async => value = config;

  @override
  Future<void> factoryReset() async => value = const DeviceConfig();
}
