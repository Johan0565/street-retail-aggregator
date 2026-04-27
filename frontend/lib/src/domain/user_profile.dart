class UserProfile {
  final int id;
  final String name;
  final String inn;
  final String phone;
  final String businessCategory;
  final int? businessCategoryId; // <-- ДОБАВИЛИ ID

  UserProfile({
    required this.id,
    required this.name,
    required this.inn,
    required this.phone,
    required this.businessCategory,
    this.businessCategoryId, // <-- ДОБАВИЛИ СЮДА
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    String categoryName = 'Не выбрана';
    int? categoryId;

    if (json['targetBusinessCategory'] != null) {
      categoryName = json['targetBusinessCategory']['name'] ?? 'Не выбрана';
      categoryId = json['targetBusinessCategory']['id']; // <-- ЧИТАЕМ ID ИЗ JSON
    }

    return UserProfile(
      id: json['id'] ?? 0,
      name: json['name'] ?? json['companyName'] ?? 'Имя не указано',
      inn: json['inn'] ?? 'ИНН не указан',
      phone: json['phone'] ?? 'Телефон не указан',
      businessCategory: categoryName,
      businessCategoryId: categoryId, // <-- ПЕРЕДАЕМ В КОНСТРУКТОР
    );
  }
}