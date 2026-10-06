import '../models/category.dart';
import '../models/product.dart';

class CatalogData {
  const CatalogData({required this.categories, required this.products});
  final List<Category> categories;
  final List<Product> products;
}

abstract interface class CatalogRepository {
  Future<CatalogData> loadCatalog();
}
