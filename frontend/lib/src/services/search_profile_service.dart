import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/search_profile.dart';

/// API-клиент для работы с проектами поиска арендатора.
class SearchProfileService {
  static String get _baseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8080/api';
    } else {
      return 'http://127.0.0.1:8080/api';
    }
  }

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<Options> _authOptions() async {
    final token = await _storage.read(key: 'jwt_token');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  CRUD проектов поиска
  // ─────────────────────────────────────────────────────────────────────────

  /// Получить все мои проекты поиска.
  Future<List<SearchProfile>> getMyProfiles() async {
    try {
      final response = await _dio.get(
        '/search-profiles',
        options: await _authOptions(),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data
            .map((json) => SearchProfile.fromJson(json as Map<String, dynamic>))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      print('Ошибка загрузки профилей: ${e.response?.statusCode} - ${e.response?.data}');
      return [];
    }
  }

  /// Создать новый профиль поиска.
  Future<SearchProfile?> createProfile(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(
        '/search-profiles',
        data: data,
        options: await _authOptions(),
      );
      if (response.statusCode == 201) {
        return SearchProfile.fromJson(response.data as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      print('Ошибка создания профиля: ${e.response?.statusCode} - ${e.response?.data}');
      return null;
    }
  }

  /// Обновить профиль поиска.
  Future<SearchProfile?> updateProfile(int id, Map<String, dynamic> data) async {
    try {
      final response = await _dio.put(
        '/search-profiles/$id',
        data: data,
        options: await _authOptions(),
      );
      if (response.statusCode == 200) {
        return SearchProfile.fromJson(response.data as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      print('Ошибка обновления профиля: ${e.response?.data}');
      return null;
    }
  }

  /// Удалить профиль поиска.
  Future<bool> deleteProfile(int id) async {
    try {
      final response = await _dio.delete(
        '/search-profiles/$id',
        options: await _authOptions(),
      );
      return response.statusCode == 204;
    } on DioException catch (e) {
      print('Ошибка удаления: ${e.response?.data}');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  ⭐ Ключевой метод: скоринг помещений по профилю
  // ─────────────────────────────────────────────────────────────────────────

  /// Получить все помещения со скорингом по конкретному профилю.
  /// Результат уже отсортирован по убыванию totalScore.
  Future<List<ScoredProperty>> getScoredProperties(int profileId) async {
    try {
      final response = await _dio.get(
        '/search-profiles/$profileId/scored-properties',
        options: await _authOptions(),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data
            .map((json) => ScoredProperty.fromJson(json as Map<String, dynamic>))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      print('Ошибка скоринга: ${e.response?.statusCode} - ${e.response?.data}');
      return [];
    }
  }
}
