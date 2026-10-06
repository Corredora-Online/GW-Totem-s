class Category {
  const Category({
    required this.id,
    required this.name,
    required this.sortOrder,
    this.visible = true,
  });

  final String id;
  final String name;
  final int sortOrder;
  final bool visible;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: json['id'] as String,
    name: json['name'] as String,
    sortOrder: json['sortOrder'] as int,
    visible: json['visible'] as bool? ?? true,
  );
}
