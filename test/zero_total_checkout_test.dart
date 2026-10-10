import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gournet_kiosk/data/local/payment_audit_repository.dart';
import 'package:gournet_kiosk/data/mock/mock_config_repository.dart';
import 'package:gournet_kiosk/data/mock/mock_order_repository.dart';
import 'package:gournet_kiosk/domain/models/cart_item.dart';
import 'package:gournet_kiosk/domain/models/device_config.dart';
import 'package:gournet_kiosk/domain/models/product.dart';
import 'package:gournet_kiosk/features/checkout/checkout_screen.dart';
import 'package:gournet_kiosk/services/payment/payment_gateway.dart';
import 'package:gournet_kiosk/state/app_providers.dart';
import 'package:gournet_kiosk/state/cart/cart_controller.dart';
import 'package:gournet_kiosk/state/checkout/checkout_controller.dart';
import 'package:gournet_kiosk/state/device_config_controller.dart';

const _freeProduct = Product(
  id: '106',
  sku: 'GYD-L1-048',
  name: 'Muffin de chocolate',
  description: '',
  price: 0,
  categoryId: 'pasteleria',
  image: '',
  available: true,
  tags: [],
  modifierGroups: [],
);

class _UnusedPaymentGateway implements PaymentGateway {
  int calls = 0;

  @override
  Future<PaymentResult> pay({
    required int amount,
    required String transactionId,
    required int ticketNumber,
  }) async {
    calls++;
    throw StateError('No debe enviarse una venta de monto cero al POS');
  }

  @override
  Future<PaymentCancellationResult> cancelActivePayment() async {
    throw StateError('No hay una venta que cancelar');
  }
}

class _UnusedPaymentAudit extends PaymentAuditRepository {
  int calls = 0;

  @override
  Future<PaymentAuditBeginResult> begin({
    required String transactionId,
    required int orderNumber,
    required int amount,
  }) async {
    calls++;
    throw StateError('Un pedido gratuito no inicia auditoría de cobro');
  }
}

void main() {
  test(
    'registra un pedido de total cero sin llamar al POS ni auditar cobro',
    () async {
      const config = DeviceConfig(apiKey: 'test', branchCode: 'test-tus');
      final configRepository = MockConfigRepository()..value = config;
      final orderRepository = MockOrderRepository();
      final gateway = _UnusedPaymentGateway();
      final audit = _UnusedPaymentAudit();
      final container = ProviderContainer(
        overrides: [
          initialDeviceConfigProvider.overrideWithValue(config),
          configRepositoryProvider.overrideWithValue(configRepository),
          orderRepositoryProvider.overrideWithValue(orderRepository),
          paymentGatewayProvider.overrideWithValue(gateway),
          paymentAuditRepositoryProvider.overrideWithValue(audit),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(cartProvider.notifier)
          .add(
            const CartItem(
              id: 'line-1',
              product: _freeProduct,
              quantity: 1,
              modifiers: [],
            ),
          );

      await container.read(checkoutProvider.notifier).start();

      expect(container.read(checkoutProvider).stage, CheckoutStage.approved);
      expect(orderRepository.orders, hasLength(1));
      expect(orderRepository.orders.single.number, 0);
      expect(orderRepository.orders.single.total, 0);
      expect(orderRepository.orders.single.paymentReference, '0');
      expect(orderRepository.orders.single.getnetTransaction, isNull);
      expect(configRepository.value.nextOrderNumber, 1);
      expect(gateway.calls, 0);
      expect(audit.calls, 0);

      await container.read(checkoutProvider.notifier).start();
      expect(orderRepository.orders, hasLength(1));
    },
  );

  testWidgets('la pantalla del pedido gratuito no señala el POS', (
    tester,
  ) async {
    const config = DeviceConfig(apiKey: 'test', branchCode: 'test-tus');
    final container = ProviderContainer(
      overrides: [
        initialDeviceConfigProvider.overrideWithValue(config),
        configRepositoryProvider.overrideWithValue(MockConfigRepository()),
        orderRepositoryProvider.overrideWithValue(MockOrderRepository()),
        paymentGatewayProvider.overrideWithValue(_UnusedPaymentGateway()),
        paymentAuditRepositoryProvider.overrideWithValue(_UnusedPaymentAudit()),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(cartProvider.notifier)
        .add(
          const CartItem(
            id: 'line-1',
            product: _freeProduct,
            quantity: 1,
            modifiers: [],
          ),
        );
    await container.read(checkoutProvider.notifier).start();
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const CheckoutScreen()),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    expect(find.text('¡Pedido confirmado!'), findsOneWidget);
    expect(find.byKey(const Key('payment-terminal-indicator')), findsNothing);
    expect(find.byKey(const Key('cancel-payment-button')), findsNothing);
  });
}
