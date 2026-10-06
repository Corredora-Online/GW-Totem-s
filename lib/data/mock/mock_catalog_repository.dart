import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/models/category.dart';
import '../../domain/models/product.dart';
import '../../domain/repositories/catalog_repository.dart';

class MockCatalogRepository implements CatalogRepository {
  @override
  Future<CatalogData> loadCatalog() async {
    final source = await rootBundle.loadString('assets/data/catalog.json');
    final json = jsonDecode(source) as Map<String, dynamic>;
    final categories =
        (json['categories'] as List<dynamic>)
            .map((item) => Category.fromJson(item as Map<String, dynamic>))
            .where((item) => item.visible)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final products = (json['products'] as List<dynamic>)
        .map((item) => Product.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    return CatalogData(categories: categories, products: products);
  }
}
