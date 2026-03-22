import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../screens/property.dart';


class PropertyService {
  // Используем тот же локальный IP, что и для авторизации
  final Dio _dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8080/api'));
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<List<Property>> getAllProperties() async {
    try {
      // Достаем сохраненный при логине токен
      final token = await _storage.read(key: 'jwt_token');

      final response = await _dio.get(
        '/properties', // Вызываем эндпоинт из твоего контроллера
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => Property.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Ошибка при загрузке помещений: $e');
      return [];
    }
  }
}