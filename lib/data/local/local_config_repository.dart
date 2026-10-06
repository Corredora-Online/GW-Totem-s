import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/security/admin_pin.dart';
import '../../domain/models/device_config.dart';
import '../../domain/repositories/config_repository.dart';

typedef ConfigDirectoryResolver = Future<Directory> Function();

class LocalConfigRepository implements ConfigRepository {
  LocalConfigRepository({
    FlutterSecureStorage? secureStorage,
    ConfigDirectoryResolver? storageDirectory,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _storageDirectory = storageDirectory ?? getApplicationSupportDirectory;

  static const _version = 1;
  static const _filename = 'gournet-kiosk-config.json';
  static const _apiKeyStorageKey = 'gournet_api_key';
  static const _adminPinStorageKey = 'gournet_admin_pin_hash';

  final FlutterSecureStorage _secureStorage;
  final ConfigDirectoryResolver _storageDirectory;

  @override
  Future<DeviceConfig> load() async {
    final secrets = await _readSecrets();
    final apiKey = secrets.$1;
    final pinHash = secrets.$2.isEmpty
        ? AdminPin.hash(AdminPin.defaultPin)
        : secrets.$2;
    try {
      final directory = await _storageDirectory();
      final file = File('${directory.path}/$_filename');
      if (!await file.exists()) {
        final initial = newInstallationConfig(apiKey: apiKey, pinHash: pinHash);
        await save(initial);
        return initial;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> || decoded['version'] != _version) {
        throw const FormatException('Configuración local inválida.');
      }
      final values = decoded['settings'];
      if (values is! Map<String, dynamic>) {
        throw const FormatException('Configuración local incompleta.');
      }
      return DeviceConfig.fromJson(
        values,
        apiKey: apiKey,
        adminPinHash: pinHash,
      );
    } catch (_) {
      return newInstallationConfig(apiKey: apiKey, pinHash: pinHash);
    }
  }

  static DeviceConfig newInstallationConfig({
    String apiKey = '',
    required String pinHash,
  }) {
    if (!Platform.isWindows) {
      return DeviceConfig(apiKey: apiKey, adminPinHash: pinHash);
    }
    final suffix = const Uuid().v4().replaceAll('-', '').substring(0, 12);
    return DeviceConfig(
      deviceId: 'WIN-${suffix.toUpperCase()}',
      kioskId: 'totem-win-$suffix',
      apiKey: apiKey,
      adminPinHash: pinHash,
    );
  }

  @override
  Future<void> save(DeviceConfig config) async {
    final directory = await _storageDirectory();
    if (!await directory.exists()) await directory.create(recursive: true);
    final target = File('${directory.path}/$_filename');
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'version': _version, 'settings': config.toJson()}),
      flush: true,
    );
    await _writeSecrets(config);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  @override
  Future<void> factoryReset() async {
    final directory = await _storageDirectory();
    for (final filename in const [
      _filename,
      'gournet-catalog-cache.json',
      'gournet-order-outbox.json',
      'gournet-payment-audit.json',
    ]) {
      final file = File('${directory.path}/$filename');
      if (await file.exists()) await file.delete();
    }
    final imageDirectory = Directory(
      '${directory.path}/gournet-catalog-images',
    );
    if (await imageDirectory.exists()) {
      await imageDirectory.delete(recursive: true);
    }
    await _secureStorage.delete(key: _apiKeyStorageKey);
    await _secureStorage.delete(key: _adminPinStorageKey);
  }

  Future<(String, String)> _readSecrets() async {
    try {
      return (
        await _secureStorage.read(key: _apiKeyStorageKey) ?? '',
        await _secureStorage.read(key: _adminPinStorageKey) ?? '',
      );
    } catch (_) {
      return ('', '');
    }
  }

  Future<void> _writeSecrets(DeviceConfig config) async {
    await _secureStorage.write(key: _apiKeyStorageKey, value: config.apiKey);
    await _secureStorage.write(
      key: _adminPinStorageKey,
      value: config.adminPinHash,
    );
  }
}
