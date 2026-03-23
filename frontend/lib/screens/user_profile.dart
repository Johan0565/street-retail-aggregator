class UserProfile {
  final int id;
  final String name;
  final String inn;
  final String phone;
  final String businessCategory;

  UserProfile({
    required this.id,
    required this.name,
    required this.inn,
    required this.phone,
    required this.businessCategory,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    // Безопасно парсим вложенный объект категории, если он есть
    String categoryName = 'Не выбрана';
    if (json['targetBusinessCategory'] != null) {
      categoryName = json['targetBusinessCategory']['name'] ?? 'Не выбрана';
    }

    return UserProfile(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Имя не указано',
      inn: json['inn'] ?? 'ИНН не указан',
      phone: json['phone'] ?? 'Телефон не указан',
      businessCategory: categoryName,
    );
  }
}