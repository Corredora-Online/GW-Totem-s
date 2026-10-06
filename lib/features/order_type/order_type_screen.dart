import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brand_mark.dart';
import '../../domain/models/device_config.dart';
import '../../domain/models/order.dart';
import '../../state/device_config_controller.dart';
import '../../state/session/session_controller.dart';

class OrderTypeScreen extends ConsumerWidget {
  const OrderTypeScreen({super.key});

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    OrderType type,
  ) async {
    final config = ref.read(deviceConfigProvider);
    if (config.operatingMode == OperatingMode.integrated && !config.online) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.cloud_off_rounded,
            color: AppColors.warning,
            size: 56,
          ),
          title: const Text(
            'Servicio temporalmente no disponible',
            textAlign: TextAlign.center,
          ),
          content: const Text(
            'Estamos intentando recuperar la conexión con la cocina.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('REINTENTAR'),
            ),
          ],
        ),
      );
      return;
    }
    ref.read(sessionProvider.notifier).setOrderType(type);
    if (context.mounted) context.go('/catalog');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(deviceConfigProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: BrandMark(
                  showRestaurant: MediaQuery.sizeOf(context).width >= 520,
                ),
              ),
              const Spacer(),
              Text(
                '¿Dónde disfrutarás\ntu pedido?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 32),
              Flexible(
                flex: 4,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontal = constraints.maxWidth >= 460;
                    final buttons = <Widget>[
                      if (config.allowEatIn)
                        _OrderTypeCard(
                          key: const Key('eat-in-button'),
                          icon: Icons.restaurant_rounded,
                          title: 'Comer aquí',
                          subtitle: 'Disfruta tu pedido en el restaurante',
                          onTap: () => _select(context, ref, OrderType.eatIn),
                        ),
                      if (config.allowTakeAway)
                        _OrderTypeCard(
                          key: const Key('take-away-button'),
                          icon: Icons.shopping_bag_rounded,
                          title: 'Para llevar',
                          subtitle: 'Te lo preparamos para llevar',
                          onTap: () =>
                              _select(context, ref, OrderType.takeAway),
                        ),
                    ];
                    if (buttons.length == 1) {
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 520,
                            maxHeight: 520,
                          ),
                          child: buttons.first,
                        ),
                      );
                    }
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 1100,
                          maxHeight: 520,
                        ),
                        child: horizontal
                            ? Row(
                                children: [
                                  Expanded(child: buttons[0]),
                                  const SizedBox(width: 28),
                                  Expanded(child: buttons[1]),
                                ],
                              )
                            : Column(
                                children: [
                                  Expanded(child: buttons[0]),
                                  const SizedBox(height: 20),
                                  Expanded(child: buttons[1]),
                                ],
                              ),
                      ),
                    );
                  },
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderTypeCard extends StatelessWidget {
  const _OrderTypeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(32),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 280 || constraints.maxHeight < 250;
          final tiny = constraints.maxHeight < 190;
          final iconExtent = tiny
              ? 50.0
              : compact
              ? 72.0
              : 96.0;
          return Container(
            padding: EdgeInsets.all(
              tiny
                  ? 10
                  : compact
                  ? 16
                  : 28,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppColors.border, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: iconExtent,
                  height: iconExtent,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFDE8F3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: tiny
                        ? 28
                        : compact
                        ? 38
                        : 50,
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(
                  height: tiny
                      ? 6
                      : compact
                      ? 12
                      : 22,
                ),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: tiny
                        ? 20
                        : compact
                        ? 24
                        : 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (!tiny) ...[
                  SizedBox(height: compact ? 5 : 8),
                  Text(
                    subtitle,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: compact ? 13 : 16,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    ),
  );
}
