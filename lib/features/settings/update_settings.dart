import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/updates/release_updater.dart';
import '../../state/device_config_controller.dart';
import '../../state/update_controller.dart';

class UpdateSettings extends ConsumerWidget {
  const UpdateSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(updateProvider);
    final config = ref.watch(deviceConfigProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Actualizaciones · ${AppRelease.version} (${AppRelease.build})',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(update.message),
            const SizedBox(height: 12),
            Text(
              'Fuente: ${AppRelease.repository}. La instalación espera a que no haya clientes ni pagos pendientes.',
            ),
            const SizedBox(height: 12),
            Text(
              'Actualizaciones automáticas: ${config.autoUpdates ? "activadas" : "desactivadas"}',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: update.busy
                  ? null
                  : () => ref
                        .read(updateProvider.notifier)
                        .check(screenIdle: () => false, manual: true),
              icon: const Icon(Icons.system_update),
              label: const Text('Buscar y preparar actualización'),
            ),
          ],
        ),
      ),
    );
  }
}
