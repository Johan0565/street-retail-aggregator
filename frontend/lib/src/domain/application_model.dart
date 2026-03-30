import 'property.dart';

class ApplicationModel {
  final int id;
  final String status;
  final String coverLetter;
  final String createdAt;
  final Property property;

  ApplicationModel({
    required this.id,
    required this.status,
    required this.coverLetter,
    required this.createdAt,
    required this.property,
  });

  factory ApplicationModel.fromJson(Map<String, dynamic> json) {
    return ApplicationModel(
      id: json['id'] ?? 0,
      status: json['status'] ?? 'PENDING',
      coverLetter: json['coverLetter'] ?? '',
      createdAt: json['createdAt'] ?? '',
      // Парсим вложенный объект помещения, используя существующий метод
      property: Property.fromJson(json['property'] ?? {}),
    );
  }
}