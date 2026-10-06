import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/models/device_config.dart';
import '../../state/device_config_controller.dart';
import '../../state/session/session_reset.dart';

class DeveloperScreen extends ConsumerWidget {
  const DeveloperScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(deviceConfigProvider);
    final controller = ref.read(deviceConfigProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.close_rounded),
        ),
        title: const Text(
          'Modo desarrollo',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: AppColors.textPrimary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(28),
              children: [
                const _DevNotice(),
                const SizedBox(height: 22),
                _SettingCard(
                  title: 'Operating Mode',
                  icon: Icons.hub_outlined,
                  child: SegmentedButton<OperatingMode>(
                    segments: const [
                      ButtonSegment(
                        value: OperatingMode.standalone,
                        label: Text('Standalone'),
                        icon: Icon(Icons.offline_bolt_outlined),
                      ),
                      ButtonSegment(
                        value: OperatingMode.integrated,
                        label: Text('Integrated'),
                        icon: Icon(Icons.cloud_outlined),
                      ),
                    ],
                    selected: {config.operatingMode},
                    onSelectionChanged: (value) =>
                        controller.setOperatingMode(value.first),
                  ),
                ),
                _SettingCard(
                  title: 'Internet',
                  icon: Icons.wifi_rounded,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Online')),
                      ButtonSegment(value: false, label: Text('Offline')),
                    ],
                    selected: {config.online},
                    onSelectionChanged: (value) =>
                        controller.setOnline(value.first),
                  ),
                ),
                _SettingCard(
                  title: 'Payment',
                  icon: Icons.credit_card_rounded,
                  child: SegmentedButton<MockPaymentOutcome>(
                    segments: const [
                      ButtonSegment(
                        value: MockPaymentOutcome.approved,
                        label: Text('Approved'),
                      ),
                      ButtonSegment(
                        value: MockPaymentOutcome.declined,
                        label: Text('Declined'),
                      ),
                    ],
                    selected: {config.paymentOutcome},
                    onSelectionChanged: (value) =>
                        controller.setPaymentOutcome(value.first),
                  ),
                ),
                _SettingCard(
                  title: 'Printer',
                  icon: Icons.print_rounded,
                  child: SegmentedButton<MockPrinterState>(
                    segments: const [
                      ButtonSegment(
                        value: MockPrinterState.ready,
                        label: Text('Ready'),
                      ),
                      ButtonSegment(
                        value: MockPrinterState.noPaper,
                        label: Text('No paper'),
                      ),
                    ],
                    selected: {config.printerState},
                    onSelectionChanged: (value) =>
                        controller.setPrinterState(value.first),
                  ),
                ),
                _SettingCard(
                  title: 'DTE',
                  icon: Icons.receipt_long_rounded,
                  child: SegmentedButton<MockDteOutcome>(
                    segments: const [
                      ButtonSegment(
                        value: MockDteOutcome.success,
                        label: Text('Success'),
                      ),
                      ButtonSegment(
                        value: MockDteOutcome.error,
                        label: Text('Error'),
                      ),
                    ],
                    selected: {config.dteOutcome},
                    onSelectionChanged: (value) =>
                        controller.setDteOutcome(value.first),
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(sessionResetProvider)();
                    controller.reset();
                    context.go('/');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                  ),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('RESET APP'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DevNotice extends StatelessWidget {
  const _DevNotice();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFFFDE8F3),
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Row(
      children: [
        Icon(Icons.science_outlined, color: AppColors.primary, size: 34),
        SizedBox(width: 14),
        Expanded(
          child: Text(
            'Estos controles sólo cambian proveedores mock. No activan hardware ni servicios reales.',
            style: TextStyle(fontWeight: FontWeight.w700, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({
    required this.title,
    required this.icon,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 590;
        final label = Row(
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ],
        );
        return compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label,
                  const SizedBox(height: 14),
                  SizedBox(width: double.infinity, child: child),
                ],
              )
            : Row(
                children: [
                  Expanded(child: label),
                  child,
                ],
              );
      },
    ),
  );
}
