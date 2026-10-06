import 'modifier.dart';

class Product {
  const Product({
    required this.id,
    required this.sku,
    required this.name,
    required this.description,
    required this.price,
    required this.categoryId,
    required this.image,
    required this.available,
    required this.tags,
    required this.modifierGroups,
  });

  final String id;
  final String sku;
  final String name;
  final String description;
  final int price;
  final String categoryId;
  final String image;
  final bool available;
  final List<String> tags;
  final List<ModifierGroup> modifierGroups;

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as String,
    sku: json['sku'] as String,
    name: json['name'] as String,
    description: json['description'] as String,
    price: json['price'] as int,
    categoryId: json['categoryId'] as String,
    image: json['image'] as String,
    available: json['available'] as bool? ?? true,
    tags: List<String>.from(json['tags'] as List<dynamic>? ?? const []),
    modifierGroups: (json['modifierGroups'] as List<dynamic>? ?? const [])
        .map((item) => ModifierGroup.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
  );
}
