import 'property.dart';

class ApplicationModel {
  final int id;
  final String status;
  final String coverLetter;
  final String createdAt;
  final Property property;

  final String? tenantName;
  final String? tenantEmail;
  final String? tenantPhone;

  final String? landlordName;
  final String? landlordPhone;

  // НОВОЕ ПОЛЕ: Причина отказа
  final String? rejectionReason;

  ApplicationModel({
    required this.id,
    required this.status,
    required this.coverLetter,
    required this.createdAt,
    required this.property,
    this.tenantName,
    this.tenantEmail,
    this.tenantPhone,
    this.landlordName,
    this.landlordPhone,
    this.rejectionReason,
  });

  factory ApplicationModel.fromJson(Map<String, dynamic> json) {
    final tenantJson = json['tenant'];
    final landlordJson = json['landlord'];

    return ApplicationModel(
      id: json['id'] ?? 0,
      status: json['status'] ?? 'PENDING',
      coverLetter: json['coverLetter'] ?? '',
      createdAt: json['createdAt'] ?? '',
      property: Property.fromJson(json['property'] ?? {}),
      tenantName: tenantJson?['name'],
      tenantEmail: tenantJson?['email'],
      tenantPhone: tenantJson?['phone'],
      landlordName: landlordJson?['name'],
      landlordPhone: landlordJson?['phone'],
      // Парсим причину отказа
      rejectionReason: json['rejectionReason'],
    );
  }
}