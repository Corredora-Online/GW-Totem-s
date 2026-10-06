import 'modifier.dart';
import 'product.dart';

class CartItem {
  const CartItem({
    required this.id,
    required this.product,
    required this.quantity,
    required this.modifiers,
  });

  final String id;
  final Product product;
  final int quantity;
  final List<SelectedModifier> modifiers;

  int get unitPrice =>
      product.price +
      modifiers.fold(0, (sum, item) => sum + item.priceAdjustment);
  int get total => unitPrice * quantity;

  CartItem copyWith({int? quantity, List<SelectedModifier>? modifiers}) =>
      CartItem(
        id: id,
        product: product,
        quantity: quantity ?? this.quantity,
        modifiers: modifiers ?? this.modifiers,
      );

  bool hasSameConfiguration(CartItem other) {
    if (product.id != other.product.id ||
        modifiers.length != other.modifiers.length) {
      return false;
    }
    final mine =
        modifiers.map((item) => '${item.groupId}:${item.optionId}').toList()
          ..sort();
    final theirs =
        other.modifiers
            .map((item) => '${item.groupId}:${item.optionId}')
            .toList()
          ..sort();
    return mine.join('|') == theirs.join('|');
  }
}
