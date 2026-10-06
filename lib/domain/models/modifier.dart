class ModifierOption {
  const ModifierOption({
    required this.id,
    required this.name,
    this.priceAdjustment = 0,
  });

  final String id;
  final String name;
  final int priceAdjustment;

  factory ModifierOption.fromJson(Map<String, dynamic> json) => ModifierOption(
    id: json['id'] as String,
    name: json['name'] as String,
    priceAdjustment: json['priceAdjustment'] as int? ?? 0,
  );
}

class ModifierGroup {
  const ModifierGroup({
    required this.id,
    required this.name,
    required this.required,
    required this.minSelection,
    required this.maxSelection,
    required this.options,
  });

  final String id;
  final String name;
  final bool required;
  final int minSelection;
  final int maxSelection;
  final List<ModifierOption> options;

  bool get isSingleChoice => maxSelection == 1;

  factory ModifierGroup.fromJson(Map<String, dynamic> json) => ModifierGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    required: json['required'] as bool? ?? false,
    minSelection: json['minSelection'] as int? ?? 0,
    maxSelection: json['maxSelection'] as int? ?? 1,
    options: (json['options'] as List<dynamic>? ?? const [])
        .map((item) => ModifierOption.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
  );
}

class SelectedModifier {
  const SelectedModifier({
    required this.groupId,
    required this.groupName,
    required this.optionId,
    required this.optionName,
    required this.priceAdjustment,
  });

  final String groupId;
  final String groupName;
  final String optionId;
  final String optionName;
  final int priceAdjustment;
}
