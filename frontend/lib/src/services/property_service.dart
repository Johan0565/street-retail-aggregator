import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/api_config.dart';
import '../domain/property.dart';
import '../domain/search_profile.dart';




class PropertyService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.apiUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
  ));
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Загружает полный объект по id — включая полный список картинок,
  /// которые могут отсутствовать в списочных эндпоинтах.
  Future<Property?> getPropertyById(int id) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '/properties/$id',
        options: token != null
            ? Options(headers: {'Authorization': 'Bearer $token'})
            : null,
      );
      if (response.statusCode == 200 && response.data is Map) {
        return Property.fromJson(response.data as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
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
  // Создание нового объекта недвижимости.
  // Возвращает id созданного объекта (или null при ошибке) —
  // нужен для последующей загрузки фотографий.
  Future<int?> createProperty({
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
    double? ceilingHeight,
    required bool hasWater,
    required bool hasVentilation,
    required bool hasSeparateEntrance,
    bool hasWc = false,
    bool hasParking = false,
    bool hasLoadingZone = false,
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
          'ceilingHeight': ceilingHeight,
          'hasWater': hasWater,
          'hasVentilation': hasVentilation,
          'hasSeparateEntrance': hasSeparateEntrance,
          'hasWc': hasWc,
          'hasParking': hasParking,
          'hasLoadingZone': hasLoadingZone,
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

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          final raw = data['id'];
          if (raw is num) return raw.toInt();
        }
      }
      return null;
    } catch (e) {
      print('Ошибка при создании объекта: $e');
      return null;
    }
  }

  /// Загружает фотографии помещения. Возвращает true при успехе.
  Future<bool> uploadPropertyImages(int propertyId, List<File> files) async {
    if (files.isEmpty) return true;
    try {
      final token = await _storage.read(key: 'jwt_token');

      final formData = FormData.fromMap({
        'files': [
          for (final f in files)
            await MultipartFile.fromFile(f.path, filename: f.uri.pathSegments.last),
        ],
      });

      final response = await _dio.post(
        '/properties/$propertyId/images',
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Ошибка при загрузке фото: $e');
      return false;
    }
  }

  Future<bool> deletePropertyImage(int propertyId, int imageId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.delete(
        '/properties/$propertyId/images/$imageId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> setMainPropertyImage(int propertyId, int imageId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');

      if (token == null) {
        print('Ошибка: JWT токен не найден в хранилище');
        return false;
      }

      final response = await _dio.put(
        '/properties/$propertyId/images/$imageId/main',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ),
        // Некоторые API требуют пустое тело для PUT запросов
        data: {},
      );

      // Стандартные коды успешного обновления — 200 или 204
      return response.statusCode == 200 || response.statusCode == 204;

    } on DioException catch (e) {
      // Выводим конкретную причину ошибки в консоль для отладки
      print('Dio Error: ${e.response?.statusCode} - ${e.message}');
      return false;
    } catch (e) {
      print('Системная ошибка: $e');
      return false;
    }
  }

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
  /// Запрашивает скоринг конкретного помещения. Если передан [profileId] —
  /// скоринг строится под этот проект; иначе бэкенд возьмёт первый активный.
  /// [force]=true заставляет бэкенд проигнорировать snapshot-кэш и
  /// пересчитать всё заново (для кнопки «обновить оценку»).
  Future<ScoredProperty?> scoreProperty(int propertyId, {int? profileId, bool force = false}) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final query = <String, dynamic>{};
      if (profileId != null) query['profileId'] = profileId;
      if (force) query['force'] = true;
      final response = await _dio.get(
        '/properties/$propertyId/score',
        queryParameters: query.isEmpty ? null : query,
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

  /// Запрашивает AI-объяснение оценки помещения под конкретный [profileId]
  /// (если не передан — под первый активный проект арендатора).
  /// Таймаут увеличен до 45 с — LLM может думать долго.
  Future<String?> explainScore(int propertyId, {int? profileId}) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '/properties/$propertyId/score-explain',
        queryParameters: profileId != null ? {'profileId': profileId} : null,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          receiveTimeout: const Duration(seconds: 45),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        return response.data['explanation'] as String?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<Property>> getAllProperties() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '/properties',
        options: token != null
            ? Options(headers: {'Authorization': 'Bearer $token'})
            : null,
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => Property.fromJson(json)).toList();
      }
      return [];
    } on DioException catch (_) {
      return [];
    } catch (_) {
      return [];
    }
  }
}