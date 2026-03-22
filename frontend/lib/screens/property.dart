class Property {
  final int id;
  final String title;
  final String description;
  final String address;
  final double latitude;
  final double longitude;
  final double pricePerMonth;
  final int powerKw;
  final bool hasWater;
  final bool hasVentilation;
  final bool hasSeparateEntrance;

  Property({
    required this.id,
    required this.title,
    required this.description,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.pricePerMonth,
    required this.powerKw,
    required this.hasWater,
    required this.hasVentilation,
    required this.hasSeparateEntrance,
  });

  factory Property.fromJson(Map<String, dynamic> json) {
    return Property(
      id: json['id'] ?? 0,
      title: json['title'] ?? 'Без названия',
      description: json['description'] ?? 'Описание отсутствует',
      address: json['address'] ?? 'Адрес не указан',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      pricePerMonth: (json['pricePerMonth'] as num?)?.toDouble() ?? 0.0,
      powerKw: json['powerKw'] ?? 0,
      hasWater: json['hasWater'] ?? false,
      hasVentilation: json['hasVentilation'] ?? false,
      hasSeparateEntrance: json['hasSeparateEntrance'] ?? false,
    );
  }
}