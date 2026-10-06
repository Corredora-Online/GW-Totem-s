import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/domain/models/cart_item.dart';
import 'package:gournet_kiosk/domain/models/order.dart';
import 'package:gournet_kiosk/domain/models/product.dart';
import 'package:gournet_kiosk/state/cart/cart_controller.dart';
import 'package:gournet_kiosk/state/session/session_controller.dart';
import 'package:gournet_kiosk/state/session/session_reset.dart';

void main() {
  test('reset de sesión vacía carrito y tipo de pedido', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const product = Product(
      id: 'p',
      sku: 'p',
      name: 'Producto',
      description: '',
      price: 1000,
      categoryId: 'demo',
      image: '',
      available: true,
      tags: [],
      modifierGroups: [],
    );
    container
        .read(cartProvider.notifier)
        .add(
          const CartItem(id: '1', product: product, quantity: 1, modifiers: []),
        );
    container.read(sessionProvider.notifier).setOrderType(OrderType.takeAway);

    container.read(sessionResetProvider)();

    expect(container.read(cartProvider), isEmpty);
    expect(container.read(sessionProvider).orderType, isNull);
  });
}
