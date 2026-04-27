import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/property.dart';
import '../domain/search_profile.dart';




class PropertyService {
  // Используем тот же локальный IP, что и для авторизации
  static String get _baseUrl {
    if (Platform.isAndroid) {
      // Для Android-эмулятора 10.0.2.2 — это "хост-машина" (твой комп)
      return 'http://10.0.2.2:8080/api';
    } else {
      // Для Windows Desktop или iOS симулятора
      return 'http://127.0.0.1:8080/api';
    }
  }

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl, // Используем наш умный URL
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  Future<bool> toggleFavorite(int propertyId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.post(
        '/properties/$propertyId/favorite', // Эндпоинт твоего бэкенда
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Ошибка при изменении избранного: $e');
      return false;
    }
  }
  Future<List<Property>> getMyProperties() async {
    try {
      final token = await _storage.read(key: 'jwt_token');

      // Предполагаем, что на бэкенде есть эндпоинт для своих объектов.
      // Если он называется иначе (например, /properties/landlord), измени строку ниже:
      final response = await _dio.get(
        '/properties/my',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => Property.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Ошибка при загрузке моих объектов: $e');
      return [];
    }
  }
  // Создание нового объекта недвижимости
  // Создание нового объекта недвижимости
  // Создание нового объекта недвижимости
  Future<bool> createProperty({
    required String title,
    required String description,
    required String address,
    required double latitude,
    required double longitude,
    required double areaSqm,
    required double pricePerMonth,
    // Новые базовые
    required String propertyType,
    required String dealType,
    // Новые финансовые
    bool taxIncluded = false,
    bool utilityIncluded = false,
    int? depositMonths,
    // Новые технические
    required int powerKw,
    required bool hasWater,
    required bool hasVentilation,
    required bool hasSeparateEntrance,
    String? repairState,
    String? layout,
    String? cadastralNumber,
    String? accessType,
    String? heatingType,
    String? furnitureState,
    bool isOccupied = false,
    // Контакты
    required String contactName,
    required String contactPhone,
  }) async {
    try {
      final token = await _storage.read(key: 'jwt_token');

      final response = await _dio.post(
        '/properties',
        data: {
          'title': title,
          'description': description,
          'address': address,
          'latitude': latitude,
          'longitude': longitude,
          'areaSqm': areaSqm,
          'pricePerMonth': pricePerMonth,
          'propertyType': propertyType, // Отправляем Enum строкой (например "OFFICE")
          'dealType': dealType,
          'taxIncluded': taxIncluded,
          'utilityIncluded': utilityIncluded,
          'depositMonths': depositMonths,
          'powerKw': powerKw,
          'hasWater': hasWater,
          'hasVentilation': hasVentilation,
          'hasSeparateEntrance': hasSeparateEntrance,
          'repairState': repairState,
          'layout': layout,
          'contactName': contactName,
          'contactPhone': contactPhone,
          'cadastralNumber': cadastralNumber,
          'accessType': accessType,
          'heatingType': heatingType,
          'furnitureState': furnitureState,
          'isOccupied': isOccupied,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Ошибка при создании объекта: $e');
      return false;
    }
  }
// Архивация (Удаление) объекта
  Future<bool> deleteProperty(int propertyId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.delete(
        '/properties/$propertyId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      print('Ошибка при удалении: $e');
      return false;
    }
  }
  Future<List<Property>> getFavoriteProperties() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '/properties/favorites', // Эндпоинт твоего бэкенда
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
      print('Ошибка при загрузке избранного: $e');
      return [];
    }
  }
  /// Запрашивает скоринг конкретного помещения относительно активного проекта
  /// поиска арендатора. Использует реальные данные 2GIS о конкурентах.
  /// Возвращает null, если нет активного проекта или произошла ошибка.
  Future<ScoredProperty?> scoreProperty(int propertyId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '/properties/$propertyId/score',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200 && response.data != null) {
        return ScoredProperty.fromJson(response.data as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<Property>> getAllProperties() async {
    try {

      final token = await _storage.read(key: 'jwt_token');
      print('>>> ТОКЕН ДЛЯ ЗАПРОСА: $token'); // Проверяем, есть ли токен

      final response = await _dio.get(
        '/properties',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        print('API вернул ${data.length} объектов');
        return data.map((json) => Property.fromJson(json)).toList();
      }
      print('>>> ОШИБКА ОТВЕТА СЕРВЕРА: ${response.statusCode} - ${response.data}');
      return [];
    } on DioException catch (e) {
      print('>>> СЕТЕВАЯ ОШИБКА DIO: ${e.response?.statusCode} - ${e.response?.data}');
      return [];
    } catch (e) {
      print('>>> ОШИБКА ПАРСИНГА: $e');
      return [];
    }
  }
}