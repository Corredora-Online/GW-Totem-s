import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatting/money.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/brand_mark.dart';
import '../../core/widgets/product_image.dart';
import '../../domain/models/category.dart';
import '../../domain/models/order.dart';
import '../../domain/models/product.dart';
import '../../state/app_providers.dart';
import '../../state/cart/cart_controller.dart';
import '../../state/device_config_controller.dart';
import '../../state/session/session_controller.dart';

const _promotionsId = '__promotions__';
const _promotionProductSkus = {
  'CAF-001',
  'PAN-001',
  'DES-001',
  'SAN-001',
  'HAM-001',
  'PIZ-001',
  'BEB-002',
  'POS-001',
};

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  String? _categoryId;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final orderType = ref.watch(sessionProvider).orderType;
    return Scaffold(
      bottomNavigationBar: const _CatalogCheckoutFooter(),
      body: SafeArea(
        child: catalog.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) =>
              _CatalogError(onRetry: () => ref.invalidate(catalogProvider)),
          data: (data) {
            final query = _query.toLowerCase().trim();
            final products = data.products
                .where((product) {
                  final matchesCategory = _categoryId == null
                      ? true
                      : _categoryId == _promotionsId
                      ? _promotionProductSkus.contains(product.sku)
                      : product.categoryId == _categoryId;
                  final matchesQuery =
                      query.isEmpty ||
                      product.name.toLowerCase().contains(query) ||
                      product.description.toLowerCase().contains(query);
                  return product.available && matchesCategory && matchesQuery;
                })
                .toList(growable: false);
            return LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 700;
                final sidebarWidth = compact ? 132.0 : 184.0;
                return Row(
                  children: [
                    SizedBox(
                      width: sidebarWidth,
                      child: _CategorySidebar(
                        categories: data.categories,
                        selectedId: _categoryId,
                        compact: compact,
                        onSelected: (value) =>
                            setState(() => _categoryId = value),
                      ),
                    ),
                    const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: AppColors.border,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _CatalogHeader(
                            orderType: orderType,
                            onQueryChanged: (value) =>
                                setState(() => _query = value),
                          ),
                          Expanded(
                            child: products.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No encontramos productos con esos filtros.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  )
                                : _ProductGrid(products: products),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _CategorySidebar extends StatelessWidget {
  const _CategorySidebar({
    required this.categories,
    required this.selectedId,
    required this.compact,
    required this.onSelected,
  });

  final List<Category> categories;
  final String? selectedId;
  final bool compact;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final items = <({String? id, String label})>[
      (id: null, label: 'Todos'),
      (id: _promotionsId, label: 'Promociones'),
      ...categories.map((item) => (id: item.id, label: item.name)),
    ];
    return ColoredBox(
      color: AppColors.surface,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 20,
              20,
              compact ? 14 : 20,
              14,
            ),
            child: const BrandMark(showRestaurant: false),
          ),
          const Text(
            'CATEGORÍAS',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: GridView.builder(
              key: const Key('category-grid'),
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
              itemCount: items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 1,
                mainAxisSpacing: 7,
                mainAxisExtent: compact ? 74 : 84,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                return _CategoryItem(
                  label: item.label,
                  icon: _categoryIcon(item.id),
                  selected: selectedId == item.id,
                  compact: compact,
                  onTap: () => onSelected(item.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryItem extends StatelessWidget {
  const _CategoryItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: Material(
      color: selected ? AppColors.primary : AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 5,
            vertical: compact ? 7 : 8,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: compact ? 24 : 27,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textPrimary,
                  fontSize: compact ? 10.5 : 9.5,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CatalogHeader extends ConsumerWidget {
  const _CatalogHeader({required this.orderType, required this.onQueryChanged});

  final OrderType? orderType;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(deviceConfigProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 22,
            compact ? 14 : 20,
            compact ? 14 : 22,
            12,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!compact)
                          Text(
                            config.restaurantName,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        Text(
                          '¿Qué quieres pedir?',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: compact ? 22 : 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!compact) ...[
                    _OrderTypePill(
                      orderType: orderType,
                      onSelected: (type) =>
                          ref.read(sessionProvider.notifier).setOrderType(type),
                    ),
                    const SizedBox(width: 10),
                  ],
                  _HeaderCartButton(compact: compact),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('product-search'),
                onChanged: onQueryChanged,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Buscar por productos',
                  hintStyle: const TextStyle(color: AppColors.textSecondary),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.textSecondary,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    vertical: compact ? 13 : 16,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrderTypePill extends StatelessWidget {
  const _OrderTypePill({required this.orderType, required this.onSelected});

  final OrderType? orderType;
  final ValueChanged<OrderType> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<OrderType>(
    key: const Key('order-type-toggle'),
    tooltip: 'Cambiar tipo de pedido',
    position: PopupMenuPosition.under,
    onSelected: onSelected,
    itemBuilder: (context) => [
      _orderTypeMenuItem(OrderType.eatIn, 'Comer aquí'),
      _orderTypeMenuItem(OrderType.takeAway, 'Para llevar'),
    ],
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            orderType == OrderType.takeAway
                ? Icons.shopping_bag_rounded
                : Icons.restaurant_rounded,
            size: 19,
            color: AppColors.primary,
          ),
          const SizedBox(width: 7),
          Text(
            orderType == OrderType.takeAway ? 'Para llevar' : 'Comer aquí',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 3),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    ),
  );

  PopupMenuItem<OrderType> _orderTypeMenuItem(OrderType type, String label) =>
      PopupMenuItem<OrderType>(
        value: type,
        child: Row(
          children: [
            Icon(
              type == OrderType.eatIn
                  ? Icons.restaurant_rounded
                  : Icons.shopping_bag_rounded,
              color: type == orderType
                  ? AppColors.primary
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
            if (type == orderType)
              const Icon(Icons.check_rounded, color: AppColors.primary),
          ],
        ),
      );
}

class _HeaderCartButton extends ConsumerWidget {
  const _HeaderCartButton({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quantity = ref.watch(cartQuantityProvider);
    final total = ref.watch(cartTotalProvider);
    return Material(
      color: quantity > 0 ? AppColors.textPrimary : AppColors.border,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('view-cart-button'),
        onTap: quantity > 0 ? () => context.push('/cart') : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 10 : 11,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(
                    Icons.shopping_bag_outlined,
                    color: Colors.white,
                    size: 25,
                  ),
                  if (quantity > 0)
                    Positioned(
                      top: -8,
                      right: -9,
                      child: Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$quantity',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (!compact) ...[
                const SizedBox(width: 11),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mi pedido',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      formatClp(total),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogCheckoutFooter extends ConsumerWidget {
  const _CatalogCheckoutFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quantity = ref.watch(cartQuantityProvider);
    final total = ref.watch(cartTotalProvider);
    final enabled = quantity > 0;
    return SafeArea(
      top: false,
      child: ColoredBox(
        color: AppColors.textPrimary,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 700;
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 26,
                vertical: compact ? 10 : 12,
              ),
              child: Row(
                children: [
                  Container(
                    width: compact ? 42 : 50,
                    height: compact ? 42 : 50,
                    decoration: BoxDecoration(
                      color: enabled
                          ? AppColors.primary
                          : const Color(0xFF3A3A45),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.shopping_bag_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          enabled
                              ? '$quantity ${quantity == 1 ? 'producto' : 'productos'}'
                              : 'Tu pedido está vacío',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFB8B8C1),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          formatClp(total),
                          style: TextStyle(
                            color: enabled
                                ? Colors.white
                                : const Color(0xFFB8B8C1),
                            fontSize: compact ? 18 : 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    key: const Key('footer-cart-button'),
                    onPressed: enabled ? () => context.push('/cart') : null,
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(compact ? 118 : 168, 52),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: const Color(0xFF777781),
                      side: BorderSide(
                        color: enabled ? Colors.white : const Color(0xFF555560),
                      ),
                    ),
                    icon: const Icon(Icons.receipt_long_rounded, size: 20),
                    label: Text(compact ? 'CARRITO' : 'VER CARRITO'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    key: const Key('footer-checkout-button'),
                    onPressed: enabled ? () => context.push('/checkout') : null,
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size(compact ? 108 : 150, 52),
                      disabledBackgroundColor: const Color(0xFF3A3A45),
                      disabledForegroundColor: const Color(0xFF777781),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                    label: const Text('PAGAR'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.products});
  final List<Product> products;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final landscape = constraints.maxWidth > constraints.maxHeight * 1.15;
      final columns = landscape ? 4 : 2;
      final rows = landscape ? 2 : 4;
      const gap = 12.0;
      final mainExtent =
          ((constraints.maxHeight - 16 - gap * (rows - 1)) / rows).clamp(
            180.0,
            420.0,
          );
      return GridView.builder(
        key: const Key('catalog-scroll'),
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
        itemCount: products.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          mainAxisExtent: mainExtent,
        ),
        itemBuilder: (context, index) => ProductCard(
          key: Key('product-${products[index].id}'),
          product: products[index],
        ),
      );
    },
  );
}

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 240 || constraints.maxHeight < 260;
      return Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        elevation: 3,
        shadowColor: const Color(0x1420202A),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/product/${product.id}'),
          child: Column(
            children: [
              Expanded(
                flex: compact ? 52 : 58,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: 'product-${product.id}',
                      child: ProductImage(source: product.image),
                    ),
                    Positioned(
                      right: compact ? 8 : 11,
                      bottom: compact ? 8 : 11,
                      child: Container(
                        width: compact ? 34 : 42,
                        height: compact ? 34 : 42,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: compact ? 23 : 28,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: compact ? 48 : 42,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 10 : 13,
                    compact ? 8 : 10,
                    compact ? 10 : 13,
                    compact ? 8 : 11,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: compact ? 14 : 17,
                          fontWeight: FontWeight.w900,
                          height: 1.12,
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 4),
                        Text(
                          product.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              formatClp(product.price),
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: compact ? 16 : 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (!compact && product.tags.isNotEmpty)
                            Container(
                              constraints: const BoxConstraints(maxWidth: 92),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF8F0),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                product.tags.first,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.success,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

IconData _categoryIcon(String? id) => switch (id) {
  null => Icons.grid_view_rounded,
  _promotionsId => Icons.local_offer_rounded,
  'cafeteria' => Icons.coffee_rounded,
  'panaderia' => Icons.bakery_dining_rounded,
  'desayunos' => Icons.breakfast_dining_rounded,
  'sandwiches' => Icons.lunch_dining_rounded,
  'hamburguesas' => Icons.fastfood_rounded,
  'ensaladas' => Icons.eco_rounded,
  'pizzas' => Icons.local_pizza_rounded,
  'platos' || 'platos-principales' => Icons.rice_bowl_rounded,
  'bebidas' => Icons.local_drink_rounded,
  'postres' => Icons.cake_rounded,
  _ => Icons.restaurant_menu_rounded,
};

class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.inventory_2_outlined,
          size: 64,
          color: AppColors.error,
        ),
        const SizedBox(height: 16),
        const Text(
          'No pudimos abrir el catálogo.',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: onRetry, child: const Text('REINTENTAR')),
      ],
    ),
  );
}
