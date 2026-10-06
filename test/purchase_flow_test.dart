import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/app.dart';
import 'package:gournet_kiosk/data/mock/mock_catalog_repository.dart';
import 'package:gournet_kiosk/data/mock/mock_config_repository.dart';
import 'package:gournet_kiosk/data/mock/mock_order_repository.dart';
import 'package:gournet_kiosk/data/mock/mock_printer_service.dart';
import 'package:gournet_kiosk/data/local/payment_audit_repository.dart';
import 'package:gournet_kiosk/domain/models/device_config.dart';
import 'package:gournet_kiosk/services/payment/payment_gateway.dart';
import 'package:gournet_kiosk/state/app_providers.dart';
import 'package:gournet_kiosk/state/device_config_controller.dart';

void main() {
  testWidgets('flujo mock desde bienvenida hasta pedido 0', (tester) async {
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const activatedConfig = DeviceConfig(
      apiKey: 'test-api-key',
      branchId: '24',
      branchCode: 'test-tus',
      branchName: 'Sucursal de prueba',
      paymentProvider: 'simulator',
    );
    final configRepository = MockConfigRepository()..value = activatedConfig;
    final orderRepository = MockOrderRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configRepositoryProvider.overrideWithValue(configRepository),
          initialDeviceConfigProvider.overrideWithValue(activatedConfig),
          catalogRepositoryProvider.overrideWithValue(MockCatalogRepository()),
          printerServiceProvider.overrideWithValue(
            const MockPrinterService(hasPaper: true),
          ),
          orderRepositoryProvider.overrideWithValue(orderRepository),
          paymentAuditRepositoryProvider.overrideWithValue(
            _InMemoryPaymentAuditRepository(),
          ),
        ],
        child: const GournetKioskApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('standby-touch-target')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('eat-in-button')));
    await tester.pump();
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byKey(const Key('catalog-scroll')).evaluate().isNotEmpty) break;
    }

    final hamburger = find.byKey(const Key('product-hamburguesa-clasica'));
    await tester.ensureVisible(hamburger);
    await tester.pump();
    await tester.tap(hamburger);
    await tester.pumpAndSettle();

    final extraCheese = find.text('Extra queso');
    await tester.ensureVisible(extraCheese);
    await tester.pump();
    await tester.tap(extraCheese);
    final addButton = find.byKey(const Key('add-product-button'));
    await tester.ensureVisible(addButton);
    await tester.pump();
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(find.text('1 producto'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('footer-cart-button')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const Key('footer-checkout-button')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    expect(find.text('¿Sigues ahí?'), findsOneWidget);
    expect(find.byKey(const Key('idle-countdown')), findsOneWidget);
    expect(find.byKey(const Key('cancel-session-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('continue-session-button')));
    await tester.pumpAndSettle();
    expect(find.text('1 producto'), findsOneWidget);

    await tester.tap(find.byKey(const Key('view-cart-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Extra queso'), findsOneWidget);
    await tester.tap(find.byKey(const Key('checkout-button')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.byKey(const Key('payment-terminal-indicator')), findsOneWidget);
    expect(find.byKey(const Key('payment-terminal-arrow-right')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const Key('success-order-number')), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('¡Pedido recibido!'), findsOneWidget);
    expect(orderRepository.orders.single.number, 0);
    expect(
      orderRepository.orders.single.uuid,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(configRepository.value.nextOrderNumber, 1);
    expect(tester.takeException(), isNull);
  });
}

class _InMemoryPaymentAuditRepository extends PaymentAuditRepository {
  @override
  Future<PaymentAuditBeginResult> begin({
    required String transactionId,
    required int orderNumber,
    required int amount,
  }) async => const PaymentAuditBeginResult.allowed('audit-entry');

  @override
  Future<void> complete(String entryId, PaymentResult result) async {}

  @override
  Future<void> markCancellationRequested(String entryId) async {}
}
