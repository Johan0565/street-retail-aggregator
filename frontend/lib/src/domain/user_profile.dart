class UserProfile {
  final int id;
  final String name;
  final String inn;
  final String phone;

  UserProfile({
    required this.id,
    required this.name,
    required this.inn,
    required this.phone,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] ?? 0,
      name: json['name'] ?? json['companyName'] ?? 'Имя не указано',
      inn: json['inn'] ?? 'ИНН не указан',
      phone: json['phone'] ?? 'Телефон не указан',
    );
  }
}