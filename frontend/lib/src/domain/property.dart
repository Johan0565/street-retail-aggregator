class Property {
  final int id;
  final String title;
  final String description;
  final String address;
  final double latitude;
  final double longitude;
  final double areaSqm; // <-- НОВОЕ
  final double pricePerMonth;

  // Базовые
  final String? propertyType;
  final String? dealType;

  // Технические
  final int powerKw;
  final bool hasWater;
  final bool hasVentilation;
  final bool hasSeparateEntrance;
  final String? repairState;
  final String? layout;

  // Контакты
  final String? contactName;
  final String? contactPhone;

  final String? cadastralNumber;
  final String? accessType;
  final String? heatingType;
  final String? furnitureState;
  final bool? isOccupied;

  Property({
    required this.id,
    required this.title,
    required this.description,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.areaSqm,
    required this.pricePerMonth,
    this.propertyType,
    this.cadastralNumber,
    this.accessType,
    this.heatingType,
    this.furnitureState,
    this.isOccupied,
    this.dealType,
    required this.powerKw,
    required this.hasWater,
    required this.hasVentilation,
    required this.hasSeparateEntrance,
    this.repairState,
    this.layout,
    this.contactName,
    this.contactPhone,
  });

  factory Property.fromJson(Map<String, dynamic> json) {
    return Property(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? 'Без названия',
      description: json['description']?.toString() ?? 'Описание отсутствует',
      address: json['address']?.toString() ?? 'Адрес не указан',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      areaSqm: (json['areaSqm'] as num?)?.toDouble() ?? 0.0,
      pricePerMonth: (json['pricePerMonth'] as num?)?.toDouble() ?? 0.0,
      propertyType: json['propertyType']?.toString(),
      dealType: json['dealType']?.toString(),
      powerKw: (json['powerKw'] as num?)?.toInt() ?? 0,
      hasWater: json['hasWater'] == true,
      hasVentilation: json['hasVentilation'] == true,
      hasSeparateEntrance: json['hasSeparateEntrance'] == true,
      repairState: json['repairState']?.toString(),
      layout: json['layout']?.toString(),
      contactName: json['contactName']?.toString(),
      contactPhone: json['contactPhone']?.toString(),
      cadastralNumber: json['cadastralNumber']?.toString(),
      accessType: json['accessType']?.toString(),
      heatingType: json['heatingType']?.toString(),
      furnitureState: json['furnitureState']?.toString(),
      isOccupied: json['isOccupied'] == true,
    );
  }
}