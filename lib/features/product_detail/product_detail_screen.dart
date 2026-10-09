import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/formatting/money.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/product_image.dart';
import '../../core/widgets/quantity_stepper.dart';
import '../../domain/models/cart_item.dart';
import '../../domain/models/modifier.dart';
import '../../domain/models/product.dart';
import '../../state/app_providers.dart';
import '../../state/cart/cart_controller.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.productId,
    this.editingItem,
  });
  final String productId;
  final CartItem? editingItem;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  int _quantity = 1;
  final Map<String, Set<String>> _selections = {};
  bool _initialized = false;

  void _initialize(Product product) {
    if (_initialized) return;
    _initialized = true;
    _quantity = widget.editingItem?.quantity ?? 1;
    for (final modifier
        in widget.editingItem?.modifiers ?? const <SelectedModifier>[]) {
      _selections
          .putIfAbsent(modifier.groupId, () => {})
          .add(modifier.optionId);
    }
    for (final group in product.modifierGroups) {
      if (group.required &&
          (_selections[group.id]?.isEmpty ?? true) &&
          group.options.isNotEmpty) {
        _selections[group.id] = {group.options.first.id};
      }
    }
  }

  void _toggle(ModifierGroup group, ModifierOption option) {
    setState(() {
      final selected = _selections.putIfAbsent(group.id, () => <String>{});
      if (group.isSingleChoice) {
        selected
          ..clear()
          ..add(option.id);
      } else if (selected.contains(option.id)) {
        selected.remove(option.id);
      } else if (selected.length < group.maxSelection) {
        selected.add(option.id);
      }
    });
  }

  List<SelectedModifier> _selectedModifiers(Product product) {
    final result = <SelectedModifier>[];
    for (final group in product.modifierGroups) {
      for (final option in group.options) {
        if (_selections[group.id]?.contains(option.id) ?? false) {
          result.add(
            SelectedModifier(
              groupId: group.id,
              groupName: group.name,
              optionId: option.id,
              optionName: option.name,
              priceAdjustment: option.priceAdjustment,
            ),
          );
        }
      }
    }
    return result;
  }

  void _add(Product product) {
    final item = CartItem(
      id: widget.editingItem?.id ?? const Uuid().v4(),
      product: product,
      quantity: _quantity,
      modifiers: _selectedModifiers(product),
    );
    if (widget.editingItem == null) {
      ref.read(cartProvider.notifier).add(item);
    } else {
      ref.read(cartProvider.notifier).replace(widget.editingItem!.id, item);
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    return Scaffold(
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            const Center(child: Text('No pudimos abrir este producto.')),
        data: (data) {
          final matches = data.products.where(
            (product) => product.id == widget.productId,
          );
          if (matches.isEmpty) {
            return const Center(child: Text('Producto no encontrado.'));
          }
          final product = matches.first;
          _initialize(product);
          return SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final landscape =
                    constraints.maxWidth >= 900 &&
                    constraints.maxWidth > constraints.maxHeight;
                final image = _ProductImage(
                  product: product,
                  onBack: () => context.pop(),
                );
                final details = _ProductOptions(
                  product: product,
                  quantity: _quantity,
                  selections: _selections,
                  onToggle: _toggle,
                  onDecrease: () => setState(
                    () => _quantity = _quantity > 1 ? _quantity - 1 : 1,
                  ),
                  onIncrease: () => setState(() => _quantity++),
                  onAdd: () => _add(product),
                  unitPrice:
                      product.price +
                      _selectedModifiers(product)
                          .fold(0, (sum, item) => sum + item.priceAdjustment),
                  editing: widget.editingItem != null,
                );
                if (landscape) {
                  return Row(
                    children: [
                      Expanded(flex: 10, child: image),
                      Expanded(flex: 11, child: details),
                    ],
                  );
                }
                return Column(
                  children: [
                    SizedBox(
                      height: (constraints.maxHeight * .28).clamp(190.0, 320.0),
                      child: image,
                    ),
                    Expanded(child: details),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.product, required this.onBack});
  final Product product;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Hero(
        tag: 'product-${product.id}',
        child: ProductImage(source: product.image),
      ),
      Positioned(
        top: 22,
        left: 22,
        child: IconButton.filled(
          onPressed: onBack,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.textPrimary,
          ),
          icon: const Icon(Icons.arrow_back_rounded),
          iconSize: 30,
        ),
      ),
    ],
  );
}

class _ProductOptions extends StatelessWidget {
  const _ProductOptions({
    required this.product,
    required this.quantity,
    required this.selections,
    required this.onToggle,
    required this.onDecrease,
    required this.onIncrease,
    required this.onAdd,
    required this.unitPrice,
    required this.editing,
  });
  final Product product;
  final int quantity;
  final Map<String, Set<String>> selections;
  final void Function(ModifierGroup, ModifierOption) onToggle;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onAdd;
  final int unitPrice;
  final bool editing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 620;
      final padding = compact ? 20.0 : 32.0;
      return ColoredBox(
        color: AppColors.surface,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(padding, padding, padding, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: product.tags
                              .map(
                                (tag) => Chip(
                                  label: Text(tag),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: const Color(0xFFEAF8F0),
                                  side: BorderSide.none,
                                  labelStyle: const TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          product.name,
                          style: Theme.of(context).textTheme.displayMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          product.description,
                          style: const TextStyle(
                            fontSize: 17,
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          formatClp(product.price),
                          style: const TextStyle(
                            fontSize: 28,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        for (final group in product.modifierGroups) ...[
                          const SizedBox(height: 30),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  group.name,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              Text(
                                group.required ? 'Obligatorio' : 'Opcional',
                                style: TextStyle(
                                  color: group.required
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...group.options.map((option) {
                            final selected =
                                selections[group.id]?.contains(option.id) ??
                                false;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Material(
                                color: selected
                                    ? const Color(0xFFFFF0F7)
                                    : AppColors.background,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  onTap: () => onToggle(group, option),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: selected
                                            ? AppColors.primary
                                            : AppColors.border,
                                        width: selected ? 2 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          group.isSingleChoice
                                              ? (selected
                                                    ? Icons.radio_button_checked
                                                    : Icons.radio_button_off)
                                              : (selected
                                                    ? Icons.check_box
                                                    : Icons
                                                          .check_box_outline_blank),
                                          color: selected
                                              ? AppColors.primary
                                              : AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            option.name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        if (option.priceAdjustment > 0)
                                          Text(
                                            '+${formatClp(option.priceAdjustment)}',
                                            style: const TextStyle(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding, 12, padding, 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Row(
                      children: [
                        QuantityStepper(
                          compact: compact,
                          quantity: quantity,
                          onDecrease: onDecrease,
                          onIncrease: onIncrease,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            key: const Key('add-product-button'),
                            onPressed: onAdd,
                            child: Text(
                              '${editing ? 'GUARDAR' : 'AGREGAR'} • ${formatClp(unitPrice * quantity)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
