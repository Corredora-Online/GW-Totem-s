import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/models/order.dart';
import '../../state/app_providers.dart';

class CompletionData {
  const CompletionData({
    required this.order,
    required this.dteSuccess,
    required this.printSuccess,
  });
  final Order order;
  final bool dteSuccess;
  final bool printSuccess;
}

class ProcessingScreen extends ConsumerStatefulWidget {
  const ProcessingScreen({super.key, required this.order});
  final Order order;

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  int _completed = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _completed = 2);
    final dte = await ref.read(dteServiceProvider).emit(order: widget.order);
    if (!mounted) return;
    setState(() => _completed = 3);
    final printed = await ref.read(printerServiceProvider).print(widget.order);
    if (!mounted) return;
    setState(() => _completed = 4);
    await ref.read(speakerServiceProvider).playSuccess();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (mounted) {
      context.go(
        '/success',
        extra: CompletionData(
          order: widget.order,
          dteSuccess: dte.success,
          printSuccess: printed.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = [
      widget.order.total == 0 ? 'Pedido sin cobro' : 'Pago confirmado',
      'Pedido registrado',
      'Pedido enviado a Gour-net',
      'Comprobante impreso',
    ];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(34),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFDE8F3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.restaurant_menu_rounded,
                      color: AppColors.primary,
                      size: 58,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Estamos preparando\ntu pedido',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Pedido #${widget.order.number}',
                    key: const Key('processing-order-number'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: AppColors.primary),
                  ),
                  const SizedBox(height: 36),
                  Container(
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      children: [
                        for (var index = 0; index < labels.length; index++)
                          _ProgressRow(
                            label: labels[index],
                            completed: _completed > index,
                            active: _completed == index,
                            last: index == labels.length - 1,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.completed,
    required this.active,
    required this.last,
  });
  final String label;
  final bool completed;
  final bool active;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 22),
    child: Row(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: completed
              ? const Icon(
                  Icons.check_circle_rounded,
                  key: ValueKey('done'),
                  color: AppColors.success,
                  size: 30,
                )
              : active
              ? const SizedBox(
                  key: ValueKey('loading'),
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              : const Icon(
                  Icons.radio_button_unchecked_rounded,
                  key: ValueKey('pending'),
                  color: AppColors.border,
                  size: 30,
                ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: completed || active
                  ? FontWeight.w800
                  : FontWeight.w500,
              color: completed || active
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}
