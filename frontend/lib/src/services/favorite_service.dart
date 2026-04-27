import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/property.dart';


class FavoriteService {
  static String get _baseUrl {
    if (Platform.isAndroid) return 'http://10.0.2.2:8080/api';
    return 'http://127.0.0.1:8080/api';
  }

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Добавление в избранное
  Future<bool> addToFavorites(int propertyId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.post(
        '/properties/$propertyId/favorite', // Используем путь из PropertyService
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Ошибка добавления в избранное: $e');
      return false;
    }
  }

  // Удаление из избранного
  Future<bool> removeFromFavorites(int propertyId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.delete(
        '/properties/$propertyId/favorite', // Используем DELETE для удаления
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      print('Ошибка удаления из избранного: $e');
      return false;
    }
  }

  // Получение списка избранного
  Future<List<Property>> getMyFavorites() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '/properties/favorites', // Используем путь из PropertyService
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => Property.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Ошибка при загрузке избранного: $e');
      return [];
    }
  }
}