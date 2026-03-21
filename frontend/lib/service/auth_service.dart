import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
// 1. Оставляем в baseUrl ТОЛЬКО хост и порт (без /api)
final Dio _dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8080'));
final FlutterSecureStorage _storage = const FlutterSecureStorage();

Future<bool> login(String email, String password) async {
  // 1. Очищаем от случайных пробелов в начале и конце
  final cleanEmail = email.trim();
  final cleanPassword = password.trim();

  // 2. Давай выведем их в консоль в кавычках, чтобы визуально убедиться,
  // что внутри нет переносов строк или других скрытых символов
  print('Пытаемся войти...');
  print('Email: "$cleanEmail"');
  print('Password: "$cleanPassword"');

  try {
    final response = await _dio.post('/api/auth/login', data: {
      'email': cleanEmail, // Отправляем очищенные данные
      'password': cleanPassword,
    });

      if (response.statusCode == 200) {
        final token = response.data['token'];
        final role = response.data['role'];

        await _storage.write(key: 'jwt_token', value: token);
        await _storage.write(key: 'user_role', value: role);

        return true;
      }
      return false;
    } on DioException catch (e) {
      // Выводим статус-код и принудительно показываем сообщение Dio, если данных нет
      final statusCode = e.response?.statusCode;
      final serverData = e.response?.data;

      print('Ошибка входа! Код: $statusCode');
      print('Ответ сервера: "${serverData}"');
      print('Системная ошибка Dio: ${e.message}');

      return false;
    } catch (e) {
      print('Неизвестная ошибка: $e');
      return false;
    }
  }
// Регистрация
  Future<bool> register(String email, String password, String role, String name, String inn, String phone) async {
    final cleanEmail = email.trim();
    final cleanPassword = password.trim();
    try {
      final response = await _dio.post('/api/auth/register', data: {
        'email': cleanEmail,
        'password': cleanPassword,
        'role': role.trim(), // 'TENANT' или 'LANDLORD'
        'name': name.trim(),
        'inn': inn.trim(),
        'phone': phone.trim(),
      });
      return response.statusCode == 200;
    } catch (e) {
      print('Ошибка регистрации: $e');
      return false;
    }
  }

  // Подтверждение кода
  Future<bool> verifyEmail(String email, String code) async {
    final cleanEmail = email.trim();
    try {
      final response = await _dio.post('/api/auth/verify', data: {
        'email': cleanEmail,
        'code': code,
      });

      if (response.statusCode == 200) {
        // Сохраняем токен, так как бэкенд выдает его после верификации
        final token = response.data['token'];
        final role = response.data['role'];
        await _storage.write(key: 'jwt_token', value: token);
        await _storage.write(key: 'user_role', value: role);
        return true;
      }
      return false;
    } catch (e) {
      print('Ошибка верификации: $e');
      return false;
    }
  }

  // Переотправка кода
  Future<bool> resendCode(String email) async {
    final cleanEmail = email.trim();
    try {
      final response = await _dio.post('/api/auth/resend-code', queryParameters: {
        'email': cleanEmail,
      });
      return response.statusCode == 200;
    } catch (e) {
      print('Ошибка переотправки: $e');
      return false;
    }
  }
  Future<String?> getToken() async {
    return await _storage.read(key: 'jwt_token');
  }
}