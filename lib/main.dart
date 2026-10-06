import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/local/local_config_repository.dart';
import 'state/device_config_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  final configRepository = LocalConfigRepository();
  final initialConfig = await configRepository.load();
  runApp(
    ProviderScope(
      overrides: [
        configRepositoryProvider.overrideWithValue(configRepository),
        initialDeviceConfigProvider.overrideWithValue(initialConfig),
      ],
      child: const GournetKioskApp(),
    ),
  );
}
