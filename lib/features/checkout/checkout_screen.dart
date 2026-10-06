import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatting/money.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/models/device_config.dart';
import '../../state/cart/cart_controller.dart';
import '../../state/checkout/checkout_controller.dart';
import '../../state/device_config_controller.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(checkoutProvider.notifier).start(),
    );
  }

  Future<void> _requestCancellation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.credit_card_off_rounded, size: 48),
        title: const Text('¿Cancelar este pago?'),
        content: const Text(
          'Sólo se cancelará si el terminal todavía no envió la operación al banco. '
          'Espera la confirmación del terminal antes de retirar la tarjeta.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('CONTINUAR PAGO'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('CANCELAR PAGO'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final accepted = await ref.read(checkoutProvider.notifier).cancelPayment();
    if (!accepted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El terminal no aceptó la cancelación. Espera el resultado del POS.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final checkout = ref.watch(checkoutProvider);
    final total = ref.watch(cartTotalProvider);
    final deviceConfig = ref.watch(deviceConfigProvider);
    ref.listen(checkoutProvider, (previous, next) {
      if (previous?.stage != CheckoutStage.approved &&
          next.stage == CheckoutStage.approved) {
        final router = GoRouter.of(context);
        Future<void>.delayed(const Duration(milliseconds: 650), () {
          if (!mounted || next.order == null) return;
          router.go('/processing', extra: next.order);
        });
      }
    });
    if (checkout.stage == CheckoutStage.declined) {
      return _PaymentDeclined(
        message: checkout.message,
        allowRetry: true,
        onRetry: () => ref.read(checkoutProvider.notifier).start(),
        onCancel: () {
          ref.read(checkoutProvider.notifier).reset();
          context.go('/cart');
        },
      );
    }
    if (checkout.stage == CheckoutStage.uncertain) {
      return _PaymentDeclined(
        title: 'Pago pendiente de revisión',
        message: checkout.message ?? 'No pudimos confirmar el resultado. Para evitar un cobro duplicado, no intentes pagar nuevamente y solicita asistencia.',
        allowRetry: false,
        onRetry: () {},
        onCancel: () {
          ref.read(checkoutProvider.notifier).reset();
          context.go('/cart');
        },
      );
    }
    final approved = checkout.stage == CheckoutStage.approved;
    final processing = checkout.stage == CheckoutStage.processing;
    final cancelling = checkout.stage == CheckoutStage.cancelling;
    final indicatorOnLeft =
        deviceConfig.paymentTerminalSide == PaymentTerminalSide.left;
    final indicatorAtBottom =
        deviceConfig.paymentTerminalVerticalPosition ==
        PaymentTerminalVerticalPosition.bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            color: approved
                                ? const Color(0xFFE6F7F0)
                                : const Color(0xFFFDE8F3),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            approved
                                ? Icons.check_rounded
                                : Icons.contactless_rounded,
                            color: approved
                                ? AppColors.success
                                : AppColors.primary,
                            size: 82,
                          ),
                        ),
                        const SizedBox(height: 30),
                        Text(
                          approved ? '¡Pago aprobado!' : 'Paga con tu tarjeta',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.displayMedium,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          formatClp(total),
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            color: approved
                                ? AppColors.success
                                : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (!approved) ...[
                          const Text(
                            'Acerca, inserta o desliza tu tarjeta\nen el terminal.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 19,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: processing
                                      ? AppColors.secondary
                                      : AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                cancelling
                                    ? 'Cancelando pago...'
                                    : processing
                                    ? 'Procesando pago...'
                                    : 'Esperando tarjeta...',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 26),
                          OutlinedButton.icon(
                            key: const Key('cancel-payment-button'),
                            onPressed: processing ? _requestCancellation : null,
                            icon: const Icon(Icons.close_rounded),
                            label: Text(
                              cancelling ? 'CANCELANDO...' : 'CANCELAR PAGO',
                            ),
                          ),
                        ] else
                          const Text(
                            'Tu pago fue confirmado correctamente.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 18,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!approved)
            Positioned(
              left: indicatorOnLeft ? 10 : null,
              right: indicatorOnLeft ? null : 10,
              top: indicatorAtBottom ? null : screenHeight * 0.5 - 68,
              bottom: indicatorAtBottom ? 26 : null,
              child: SafeArea(
                child: IgnorePointer(
                  child: _PaymentTerminalIndicator(
                    side: deviceConfig.paymentTerminalSide,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaymentTerminalIndicator extends StatefulWidget {
  const _PaymentTerminalIndicator({required this.side});

  final PaymentTerminalSide side;

  @override
  State<_PaymentTerminalIndicator> createState() =>
      _PaymentTerminalIndicatorState();
}

class _PaymentTerminalIndicatorState extends State<_PaymentTerminalIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pointsLeft = widget.side == PaymentTerminalSide.left;
    final movement = pointsLeft ? -8.0 : 8.0;
    return Semantics(
      label: pointsLeft
          ? 'Terminal de pago a la izquierda'
          : 'Terminal de pago a la derecha',
      child: Container(
        key: const Key('payment-terminal-indicator'),
        width: 112,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.primary, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PAGA AQUÍ',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => Transform.translate(
                offset: Offset(movement * _controller.value, 0),
                child: child,
              ),
              child: Icon(
                pointsLeft
                    ? Icons.keyboard_double_arrow_left_rounded
                    : Icons.keyboard_double_arrow_right_rounded,
                key: Key(
                  pointsLeft
                      ? 'payment-terminal-arrow-left'
                      : 'payment-terminal-arrow-right',
                ),
                color: AppColors.primary,
                size: 54,
              ),
            ),
            const Text(
              'USA EL POS',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentDeclined extends StatelessWidget {
  const _PaymentDeclined({
    required this.message,
    required this.allowRetry,
    required this.onRetry,
    required this.onCancel,
    this.title = 'No pudimos procesar el pago',
  });
  final String? message;
  final String title;
  final bool allowRetry;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 140,
                  height: 140,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFE9ED),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: AppColors.error,
                    size: 76,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  message ?? 'Puedes intentar nuevamente.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onCancel,
                        child: Text(allowRetry ? 'CANCELAR' : 'VOLVER'),
                      ),
                    ),
                    if (allowRetry) ...[
                      const SizedBox(width: 14),
                      Expanded(
                        child: ElevatedButton(
                          key: const Key('retry-payment-button'),
                          onPressed: onRetry,
                          child: const Text('REINTENTAR'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
