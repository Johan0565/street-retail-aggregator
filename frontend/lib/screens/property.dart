class Property {
  final int id;
  final String title;
  final double latitude;
  final double longitude;
  final double pricePerMonth;

  Property({
    required this.id,
    required this.title,
    required this.latitude,
    required this.longitude,
    required this.pricePerMonth,
  });

  factory Property.fromJson(Map<String, dynamic> json) {
    return Property(
      id: json['id'],
      title: json['title'],
      // В JSON от Spring Boot BigDecimal может прийти как int или double,
      // поэтому безопасно парсим через num
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      pricePerMonth: (json['pricePerMonth'] as num).toDouble(),
    );
  }
}