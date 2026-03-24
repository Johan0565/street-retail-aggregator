class BusinessCategory {
  final int id;
  final String name;

  BusinessCategory({required this.id, required this.name});

  factory BusinessCategory.fromJson(Map<String, dynamic> json) {
    return BusinessCategory(
      id: json['id'],
      name: json['name'],
    );
  }
}