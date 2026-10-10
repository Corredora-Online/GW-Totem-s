import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/data/remote/gournet_order_repository.dart';
import 'package:gournet_kiosk/domain/models/cart_item.dart';
import 'package:gournet_kiosk/domain/models/modifier.dart';
import 'package:gournet_kiosk/domain/models/order.dart';
import 'package:gournet_kiosk/domain/models/product.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _product = Product(
  id: '33',
  sku: 'DEMO-QR-002',
  name: 'Cappuccino clásico',
  description: '',
  price: 3800,
  categoryId: 'cafeteria',
  image: '',
  available: true,
  tags: [],
  modifierGroups: [],
);

const _modifier = SelectedModifier(
  groupId: 'leche',
  groupName: 'Leche',
  optionId: 'sin-lactosa',
  optionName: 'Leche sin lactosa',
  priceAdjustment: 500,
);

final _order = Order(
  uuid: '12345678-1234-4234-9234-123456789abc',
  number: 0,
  type: OrderType.eatIn,
  items: const [
    CartItem(
      id: 'line-1',
      product: _product,
      quantity: 2,
      modifiers: [_modifier],
    ),
  ],
  paymentStatus: PaymentStatus.approved,
  dteStatus: DteStatus.pending,
  syncStatus: SyncStatus.pending,
  createdAt: DateTime(2026, 9, 1, 12, 34, 56),
  paymentReference: 'MOCK-123456',
  status: SaleStatus.paymentApproved,
);

void main() {
  test(
    'mapea, encola y reintenta el mismo pedido de forma idempotente',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gournet-orders-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final requests = <http.Request>[];
      var shouldSucceed = false;
      final repository = GournetOrderRepository(
        apiKey: 'test-api-key',
        branchCode: '24',
        kioskId: 'totem-001',
        endpoint: Uri.parse('https://api.example/orders'),
        storageDirectory: () async => directory,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('', shouldSucceed ? 200 : 500);
        }),
      );
      addTearDown(repository.dispose);

      await repository.save(_order);

      expect(requests, hasLength(1));
      expect(requests.single.headers['apiKey'], 'test-api-key');
      final firstPayload =
          jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(firstPayload['tus'], '24');
      expect(firstPayload['numero'], '0');
      expect(firstPayload['origen_id'], 'totem-001-0');
      expect(firstPayload['idempotency_key'], _order.uuid);
      expect(
        firstPayload['idempotency_key'],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(firstPayload['idempotency_key'], isNot(contains('totem')));
      expect(firstPayload.containsKey('sucursal'), isFalse);
      expect(firstPayload['tipo_entrega'], 'mesa');
      expect(firstPayload['subtotal'], '8600');
      expect(firstPayload['total'], '8600');
      expect(firstPayload['estado_pago'], 'pagado');
      expect(firstPayload['metodo_pago'], 'app');
      expect(firstPayload['pago_referencia'], matches(RegExp(r'^\d{8}$')));
      expect(firstPayload['origen_creado_en'], '2026-09-01T12:34');
      expect(firstPayload['pagado_en'], '2026-09-01T12:34');
      expect(firstPayload.containsKey('items_count'), isFalse);
      final products = firstPayload['productos'] as List<dynamic>;
      expect(products, hasLength(1));
      expect(products.single['producto_id'], 33);
      expect(products.single['precio_unitario'], 4300);
      expect(products.single['total_linea'], 8600);
      expect(products.single['modificadores'], 'Leche sin lactosa');

      final queueFile = File('${directory.path}/gournet-order-outbox.json');
      final pendingBeforeRetry =
          jsonDecode(await queueFile.readAsString()) as Map<String, dynamic>;
      expect(pendingBeforeRetry['orders'], hasLength(1));

      shouldSucceed = true;
      await repository.syncPending();

      expect(requests, hasLength(2));
      final secondPayload =
          jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(secondPayload['idempotency_key'], firstPayload['idempotency_key']);
      final pendingAfterRetry =
          jsonDecode(await queueFile.readAsString()) as Map<String, dynamic>;
      expect(pendingAfterRetry['orders'], isEmpty);
    },
  );

  test('mapea para llevar como retiro', () {
    final repository = GournetOrderRepository(
      apiKey: 'test-api-key',
      client: MockClient((request) async => http.Response('', 200)),
    );
    addTearDown(repository.dispose);

    final payload = repository.buildPayload(
      Order(
        uuid: _order.uuid,
        number: _order.number,
        type: OrderType.takeAway,
        items: _order.items,
        paymentStatus: _order.paymentStatus,
        dteStatus: _order.dteStatus,
        syncStatus: _order.syncStatus,
        createdAt: _order.createdAt,
        paymentReference: _order.paymentReference,
        status: _order.status,
      ),
    );

    expect(payload['tipo_entrega'], 'retiro');
  });

  test('marca como sin cobro un pedido de total cero', () {
    final repository = GournetOrderRepository(
      apiKey: 'test-api-key',
      client: MockClient((request) async => http.Response('', 200)),
    );
    addTearDown(repository.dispose);
    const freeProduct = Product(
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
    final payload = repository.buildPayload(
      Order(
        uuid: _order.uuid,
        number: 1,
        type: OrderType.takeAway,
        items: const [
          CartItem(
            id: 'free-line',
            product: freeProduct,
            quantity: 1,
            modifiers: [],
          ),
        ],
        paymentStatus: PaymentStatus.approved,
        dteStatus: DteStatus.pending,
        syncStatus: SyncStatus.pending,
        createdAt: _order.createdAt,
        paymentReference: '0',
      ),
    );

    expect(payload['total'], '0');
    expect(payload['pago_referencia'], '0');
    expect(payload['nota_interna'], contains('sin cobro'));
    expect((payload['productos'] as List).single['precio_unitario'], 0);
  });

  test('envía el TUS alfanumérico de la sucursal', () {
    final repository = GournetOrderRepository(
      apiKey: 'test-api-key',
      tus: '5QQTw5u1K8ed',
      branchCode: '24',
      client: MockClient((request) async => http.Response('', 200)),
    );
    addTearDown(repository.dispose);

    final payload = repository.buildPayload(_order);

    expect(payload['tus'], '5QQTw5u1K8ed');
    expect(payload['tus'], isNot('24'));
  });

  test('migra pedidos pendientes desde sucursal al formato TUS', () async {
    final directory = await Directory.systemTemp.createTemp(
      'gournet-orders-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final queueFile = File('${directory.path}/gournet-order-outbox.json');
    await queueFile.writeAsString(
      jsonEncode({
        'version': 1,
        'orders': [
          {
            'sucursal': '24',
            'numero': 'totem-001-legacy',
            'origen_id': 'totem-001-legacy',
            'idempotency_key': 'pending-order',
            'origen_creado_en': '2026-09-01 12:34:56',
            'pagado_en': '2026-09-01 12:34:56',
            'pago_referencia': 'MOCK-LEGACY',
            'items_count': '1',
            'productos': <dynamic>[],
          },
        ],
      }),
    );
    late Map<String, dynamic> sentPayload;
    final repository = GournetOrderRepository(
      apiKey: 'test-api-key',
      tus: '5QQTw5u1K8ed',
      branchCode: '24',
      endpoint: Uri.parse('https://api.example/orders'),
      storageDirectory: () async => directory,
      client: MockClient((request) async {
        sentPayload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('', 200);
      }),
    );
    addTearDown(repository.dispose);

    await repository.syncPending();

    expect(sentPayload['tus'], '5QQTw5u1K8ed');
    expect(sentPayload['numero'], '20260901123456');
    expect(sentPayload['origen_id'], 'totem-001-20260901123456');
    expect(sentPayload.containsKey('sucursal'), isFalse);
    expect(sentPayload.containsKey('items_count'), isFalse);
    expect(sentPayload['origen_creado_en'], '2026-09-01T12:34');
    expect(sentPayload['pagado_en'], '2026-09-01T12:34');
    expect(sentPayload['pago_referencia'], matches(RegExp(r'^\d{8}$')));
  });
}
