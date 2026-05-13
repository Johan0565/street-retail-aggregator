import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/api_config.dart';
import '../domain/business_category.dart';


class CategoryService {
  final Dio _dio = Dio(BaseOptions(baseUrl: ApiConfig.apiUrl));
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<List<BusinessCategory>> getCategories() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      // Предполагаем, что на бэке есть или будет контроллер для категорий
      final response = await _dio.get(
        '/categories',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => BusinessCategory.fromJson(json)).toList();
      }
      return _getFallbackCategories();
    } catch (e) {
      print('Ошибка загрузки категорий, используем резервный список: $e');
      return _getFallbackCategories();
    }
  }

  // Временный список, пока не настроишь БД
  List<BusinessCategory> _getFallbackCategories() {
    return [
      BusinessCategory(id: 1, name: 'Кофейня / Пекарня'),
      BusinessCategory(id: 2, name: 'Пункт выдачи заказов (ПВЗ)'),
      BusinessCategory(id: 3, name: 'Продуктовый магазин'),
      BusinessCategory(id: 4, name: 'Аптека'),
      BusinessCategory(id: 5, name: 'Салон красоты / Барбершоп'),
      BusinessCategory(id: 6, name: 'Одежда и обувь'),
      BusinessCategory(id: 7, name: 'Спортзал / Фитнес'),
    ];
  }

  /// Плоский список категорий в виде Map — удобен для Dropdown в форме профиля поиска.
  Future<List<Map<String, dynamic>>> getAllCategories() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '/categories/flat',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((e) => {'id': e['id'], 'name': e['name']}).toList();
      }
    } catch (_) {}
    // Fallback: преобразуем из статического списка
    return _getFallbackCategories()
        .map((c) => {'id': c.id, 'name': c.name})
        .toList();
  }
}