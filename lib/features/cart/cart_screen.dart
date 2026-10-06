import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatting/money.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/product_image.dart';
import '../../core/widgets/quantity_stepper.dart';
import '../../domain/models/cart_item.dart';
import '../../state/cart/cart_controller.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        iconSize: 30,
                        style: IconButton.styleFrom(
                          fixedSize: const Size(56, 56),
                          foregroundColor: AppColors.textPrimary,
                          backgroundColor: AppColors.surface,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Text(
                        'Tu pedido',
                        style: Theme.of(context).textTheme.displayMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (items.isEmpty)
                    const Expanded(child: _EmptyCart())
                  else ...[
                    Expanded(
                      child: ListView.separated(
                        key: const Key('cart-list'),
                        itemCount: items.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 14),
                        itemBuilder: (context, index) =>
                            _CartLine(item: items[index]),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 18),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Subtotal',
                                style: TextStyle(
                                  fontSize: 17,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                formatClp(total),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Divider(height: 1),
                          ),
                          Row(
                            children: [
                              const Text(
                                'TOTAL',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                formatClp(total),
                                style: const TextStyle(
                                  fontSize: 30,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final compact = constraints.maxWidth < 620;
                              final buttons = [
                                OutlinedButton(
                                  onPressed: () => context.go('/catalog'),
                                  child: const Text('SEGUIR COMPRANDO'),
                                ),
                                ElevatedButton(
                                  key: const Key('checkout-button'),
                                  onPressed: () => context.go('/checkout'),
                                  child: const Text('IR A PAGAR'),
                                ),
                              ];
                              return compact
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        buttons[0],
                                        const SizedBox(height: 12),
                                        buttons[1],
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        Expanded(child: buttons[0]),
                                        const SizedBox(width: 14),
                                        Expanded(child: buttons[1]),
                                      ],
                                    );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CartLine extends ConsumerWidget {
  const _CartLine({required this.item});
  final CartItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ProductImage(
            source: item.product.image,
            width: 112,
            height: 112,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.product.name,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (item.modifiers.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  item.modifiers
                      .map((modifier) => modifier.optionName)
                      .join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '${item.quantity} × ${formatClp(item.unitPrice)}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    context.push('/product/${item.product.id}', extra: item),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        QuantityStepper(
          compact: true,
          quantity: item.quantity,
          onDecrease: () => ref.read(cartProvider.notifier).decrement(item.id),
          onIncrease: () => ref.read(cartProvider.notifier).increment(item.id),
        ),
      ],
    ),
  );
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.shopping_bag_outlined,
          size: 80,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 18),
        const Text(
          'Tu pedido está vacío',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => context.go('/catalog'),
          child: const Text('VER PRODUCTOS'),
        ),
      ],
    ),
  );
}
