import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/domain/models/cart_item.dart';
import 'package:gournet_kiosk/domain/models/modifier.dart';
import 'package:gournet_kiosk/domain/models/product.dart';
import 'package:gournet_kiosk/state/cart/cart_controller.dart';

const product = Product(
  id: 'hamburguesa',
  sku: 'HAM-001',
  name: 'Hamburguesa clásica',
  description: 'Demo',
  price: 8990,
  categoryId: 'hamburguesas',
  image: 'assets/images/products/cheeseburger.png',
  available: true,
  tags: [],
  modifierGroups: [],
);

const extraCheese = SelectedModifier(
  groupId: 'extras',
  groupName: 'Extras',
  optionId: 'extra-queso',
  optionName: 'Extra queso',
  priceAdjustment: 900,
);

CartItem item(
  String id, {
  int quantity = 1,
  List<SelectedModifier> modifiers = const [],
}) => CartItem(
  id: id,
  product: product,
  quantity: quantity,
  modifiers: modifiers,
);

void main() {
  late CartController cart;

  setUp(() => cart = CartController());

  test('agrega producto y calcula total', () {
    cart.add(item('one'));
    expect(cart.state, hasLength(1));
    expect(cart.state.first.total, 8990);
  });

  test('aumenta y disminuye cantidad', () {
    cart.add(item('one'));
    cart.increment('one');
    expect(cart.state.first.quantity, 2);
    expect(cart.state.first.total, 17980);
    cart.decrement('one');
    expect(cart.state.first.quantity, 1);
  });

  test('disminuir desde uno elimina la línea', () {
    cart.add(item('one'));
    cart.decrement('one');
    expect(cart.state, isEmpty);
  });

  test('elimina un producto', () {
    cart.add(item('one'));
    cart.remove('one');
    expect(cart.state, isEmpty);
  });

  test('incluye modificadores en precio y separa configuraciones', () {
    cart.add(item('normal'));
    cart.add(item('cheese', modifiers: const [extraCheese]));
    expect(cart.state, hasLength(2));
    expect(cart.state.last.unitPrice, 9890);
    expect(cart.state.fold(0, (sum, line) => sum + line.total), 18880);
  });

  test('combina líneas con la misma configuración', () {
    cart.add(item('first', modifiers: const [extraCheese]));
    cart.add(item('second', modifiers: const [extraCheese]));
    expect(cart.state, hasLength(1));
    expect(cart.state.first.quantity, 2);
  });
}
