import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/core/theme/app_theme.dart';
import 'package:gournet_kiosk/core/widgets/adaptive_kiosk_viewport.dart';
import 'package:gournet_kiosk/core/widgets/product_image.dart';
import 'package:gournet_kiosk/domain/models/product.dart';
import 'package:gournet_kiosk/domain/repositories/catalog_repository.dart';
import 'package:gournet_kiosk/features/catalog/catalog_screen.dart';
import 'package:gournet_kiosk/features/product_detail/product_detail_screen.dart';
import 'package:gournet_kiosk/state/app_providers.dart';

const fakeCatalog = CatalogData(
  categories: [],
  products: [
    Product(
      id: 'demo',
      sku: 'DEMO',
      name: 'Producto demo',
      description: 'Producto para verificar el layout responsive.',
      price: 8990,
      categoryId: 'demo',
      image: 'assets/images/products/cheeseburger.png',
      available: true,
      tags: [],
      modifierGroups: [],
    ),
  ],
);

Future<void> pumpCatalog(
  WidgetTester tester,
  Size size, {
  bool windowsViewport = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [catalogProvider.overrideWith((ref) => fakeCatalog)],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => AdaptiveKioskViewport(
          enabled: windowsViewport,
          child: child ?? const SizedBox(),
        ),
        home: const CatalogScreen(),
      ),
    ),
  );
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(SliverGrid).evaluate().isNotEmpty) break;
  }
}

Future<void> pumpProductDetail(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [catalogProvider.overrideWith((ref) => fakeCatalog)],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => AdaptiveKioskViewport(
          enabled: true,
          child: child ?? const SizedBox(),
        ),
        home: const ProductDetailScreen(productId: 'demo'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'catálogo Windows de alta resolución conserva lectura y acciones',
    (tester) async {
      await pumpCatalog(tester, const Size(1080, 1920), windowsViewport: true);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('catalog-scroll')), findsOneWidget);
      expect(find.byKey(const Key('footer-cart-button')), findsOneWidget);
      expect(find.byKey(const Key('footer-checkout-button')), findsOneWidget);
    },
  );

  testWidgets(
    'detalle en Windows vertical muestra opciones debajo de la foto y compra visible',
    (tester) async {
      await pumpProductDetail(tester, const Size(1080, 1920));
      expect(tester.takeException(), isNull);
      expect(AdaptiveKioskViewport.scaleFor(const Size(1080, 1920)), 1.5);
      final image = tester.getRect(find.byType(ProductImage));
      final title = tester.getRect(find.text('Producto demo'));
      final add = tester.getRect(find.byKey(const Key('add-product-button')));
      expect(title.top, greaterThan(image.bottom));
      expect(add.bottom, lessThanOrEqualTo(1920));
    },
  );

  testWidgets('detalle en Windows horizontal deja la foto al lado', (
    tester,
  ) async {
    await pumpProductDetail(tester, const Size(1920, 1080));
    expect(tester.takeException(), isNull);
    final image = tester.getRect(find.byType(ProductImage));
    final title = tester.getRect(find.text('Producto demo'));
    expect(title.left, greaterThan(image.right));
  });

  testWidgets('catálogo 540 × 960 sin overflow en densidad lógica SUNMI', (
    tester,
  ) async {
    await pumpCatalog(tester, const Size(540, 960));
    expect(tester.takeException(), isNull);
    final grid = tester.widget<SliverGrid>(
      find.descendant(
        of: find.byKey(const Key('catalog-scroll')),
        matching: find.byType(SliverGrid),
      ),
    );
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);

    final categoryGrid = tester.widget<SliverGrid>(
      find.descendant(
        of: find.byKey(const Key('category-grid')),
        matching: find.byType(SliverGrid),
      ),
    );
    final categoryDelegate =
        categoryGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(categoryDelegate.crossAxisCount, 1);
  });

  testWidgets('catálogo 1080 × 1920 sin overflow y con dos columnas', (
    tester,
  ) async {
    await pumpCatalog(tester, const Size(1080, 1920));
    expect(tester.takeException(), isNull);
    final grid = tester.widget<SliverGrid>(
      find.descendant(
        of: find.byKey(const Key('catalog-scroll')),
        matching: find.byType(SliverGrid),
      ),
    );
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);

    await tester.tap(find.byKey(const Key('order-type-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Para llevar'));
    await tester.pumpAndSettle();
    expect(find.text('Para llevar'), findsOneWidget);
  });

  testWidgets('catálogo 1920 × 1080 sin overflow y con cuatro columnas', (
    tester,
  ) async {
    await pumpCatalog(tester, const Size(1920, 1080));
    expect(tester.takeException(), isNull);
    final grid = tester.widget<SliverGrid>(
      find.descendant(
        of: find.byKey(const Key('catalog-scroll')),
        matching: find.byType(SliverGrid),
      ),
    );
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 4);
  });
}
