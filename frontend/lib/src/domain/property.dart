class PropertyImage {
  final int id;
  final String imageUrl;
  final bool isMain;

  PropertyImage({required this.id, required this.imageUrl, required this.isMain});

  factory PropertyImage.fromJson(Map<String, dynamic> json) {
    return PropertyImage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      imageUrl: json['imageUrl']?.toString() ?? '',
      isMain: json['isMain'] == true,
    );
  }
}

class Property {
  final int id;
  final String title;
  final String description;
  final String address;
  final double latitude;
  final double longitude;
  final double areaSqm; // <-- НОВОЕ
  final double pricePerMonth;
  final String? status; // <-- PUBLISHED, ARCHIVED, etc.

  // Базовые
  final String? propertyType;
  final String? dealType;

  // Технические
  final int powerKw;
  final bool hasWater;
  final bool hasVentilation;
  final bool hasSeparateEntrance;
  final bool hasWc;
  final bool hasParking;
  final bool hasLoadingZone;
  final double? ceilingHeight;
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
  final String? metroStation;
  final int? timeToMetro;

  final List<PropertyImage> images;

  Property({
    required this.id,
    required this.title,
    required this.description,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.areaSqm,
    required this.pricePerMonth,
    this.status,
    this.propertyType,
    this.cadastralNumber,
    this.accessType,
    this.heatingType,
    this.furnitureState,
    this.isOccupied,
    this.metroStation,
    this.timeToMetro,
    this.dealType,
    required this.powerKw,
    required this.hasWater,
    required this.hasVentilation,
    required this.hasSeparateEntrance,
    required this.hasWc,
    required this.hasParking,
    required this.hasLoadingZone,
    this.ceilingHeight,
    this.repairState,
    this.layout,
    this.contactName,
    this.contactPhone,
    this.images = const [],
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
      status: json['status']?.toString(),
      propertyType: json['propertyType']?.toString(),
      dealType: json['dealType']?.toString(),
      powerKw: (json['powerKw'] as num?)?.toInt() ?? 0,
      hasWater: json['hasWater'] == true,
      hasVentilation: json['hasVentilation'] == true,
      hasSeparateEntrance: json['hasSeparateEntrance'] == true,
      hasWc: json['hasWc'] == true,
      hasParking: json['hasParking'] == true,
      hasLoadingZone: json['hasLoadingZone'] == true,
      ceilingHeight: (json['ceilingHeight'] as num?)?.toDouble(),
      repairState: json['repairState']?.toString(),
      layout: json['layout']?.toString(),
      contactName: json['contactName']?.toString(),
      contactPhone: json['contactPhone']?.toString(),
      cadastralNumber: json['cadastralNumber']?.toString(),
      accessType: json['accessType']?.toString(),
      heatingType: json['heatingType']?.toString(),
      furnitureState: json['furnitureState']?.toString(),
      isOccupied: json['isOccupied'] == true,
      metroStation: json['metroStation']?.toString(),
      timeToMetro: (json['timeToMetro'] as num?)?.toInt(),
      images: (json['images'] as List<dynamic>?)
              ?.map((e) => PropertyImage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}