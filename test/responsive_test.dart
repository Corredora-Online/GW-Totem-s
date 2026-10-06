import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gournet_kiosk/core/theme/app_theme.dart';
import 'package:gournet_kiosk/domain/models/product.dart';
import 'package:gournet_kiosk/domain/repositories/catalog_repository.dart';
import 'package:gournet_kiosk/features/catalog/catalog_screen.dart';
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

Future<void> pumpCatalog(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [catalogProvider.overrideWith((ref) => fakeCatalog)],
      child: MaterialApp(theme: AppTheme.light, home: const CatalogScreen()),
    ),
  );
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(SliverGrid).evaluate().isNotEmpty) break;
  }
}

void main() {
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
