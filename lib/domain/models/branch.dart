class Branch {
  const Branch({
    required this.id,
    required this.name,
    this.code = '',
    this.address = '',
    this.city = '',
  });

  final String id;
  final String name;
  final String code;
  final String address;
  final String city;

  String get subtitle =>
      [address, city].where((part) => part.trim().isNotEmpty).join(' · ');
}
