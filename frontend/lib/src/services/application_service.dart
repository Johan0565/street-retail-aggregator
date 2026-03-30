import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/application_model.dart';


class ApplicationService {
  static String get _baseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8080/api';
    } else {
      return 'http://127.0.0.1:8080/api';
    }
  }

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Метод для отправки заявки
  Future<bool> createApplication(int propertyId, String coverLetter) async {
    try {
      final token = await _storage.read(key: 'jwt_token');

      final response = await _dio.post(
        '/applications',
        data: {
          'propertyId': propertyId,
          'coverLetter': coverLetter,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      // Бэкенд возвращает статус 201 CREATED при успешном создании
      return response.statusCode == 201;
    } catch (e) {
      print('Ошибка при создании заявки: $e');
      return false;
    }
  }
  Future<List<ApplicationModel>> getMyApplications() async {
    try {
      final token = await _storage.read(key: 'jwt_token');

      final response = await _dio.get(
        '/applications/my-requests',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => ApplicationModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Ошибка при загрузке заявок: $e');
      return [];
    }
  }
  // Получить входящие заявки (для Арендодателя)
  Future<List<ApplicationModel>> getIncomingApplications() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '/applications/incoming',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => ApplicationModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Ошибка при загрузке входящих заявок: $e');
      return [];
    }
  }

  // Обновить статус заявки
  // Обновить статус заявки
  // Обновить статус заявки (добавили именованный параметр rejectionReason)
  Future<bool> updateApplicationStatus(int applicationId, String newStatus, {String? rejectionReason}) async {
    try {
      final token = await _storage.read(key: 'jwt_token');

      final response = await _dio.patch(
        '/applications/$applicationId/status',
        data: {
          'status': newStatus,
          // Отправляем причину отказа, если она есть
          if (rejectionReason != null && rejectionReason.isNotEmpty) 'rejectionReason': rejectionReason,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Ошибка обновления статуса: $e');
      return false;
    }
  }

}