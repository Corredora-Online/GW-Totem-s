import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/cart_item.dart';

class CartController extends StateNotifier<List<CartItem>> {
  CartController() : super(const []);

  void add(CartItem item) {
    final index = state.indexWhere(item.hasSameConfiguration);
    if (index < 0) {
      state = [...state, item];
      return;
    }
    final existing = state[index];
    final next = [...state];
    next[index] = existing.copyWith(
      quantity: existing.quantity + item.quantity,
    );
    state = next;
  }

  void replace(String originalId, CartItem item) {
    final index = state.indexWhere((entry) => entry.id == originalId);
    if (index < 0) return;
    final next = [...state];
    next[index] = item;
    state = next;
  }

  void increment(String id) => _setQuantity(id, 1);
  void decrement(String id) => _setQuantity(id, -1);

  void _setQuantity(String id, int delta) {
    final index = state.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final quantity = state[index].quantity + delta;
    if (quantity <= 0) {
      remove(id);
      return;
    }
    final next = [...state];
    next[index] = next[index].copyWith(quantity: quantity);
    state = next;
  }

  void remove(String id) =>
      state = state.where((item) => item.id != id).toList(growable: false);
  void clear() => state = const [];
}

final cartProvider = StateNotifierProvider<CartController, List<CartItem>>(
  (ref) => CartController(),
);
final cartTotalProvider = Provider<int>(
  (ref) => ref.watch(cartProvider).fold(0, (sum, item) => sum + item.total),
);
final cartQuantityProvider = Provider<int>(
  (ref) => ref.watch(cartProvider).fold(0, (sum, item) => sum + item.quantity),
);
