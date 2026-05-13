import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/api_config.dart';
import '../domain/user_profile.dart';


class AuthService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));
final FlutterSecureStorage _storage = const FlutterSecureStorage();
Future<String?> getUserRole() async {
  return await _storage.read(key: 'user_role');
}


  Future<UserProfile?> getCurrentUserProfile() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final role = await _storage.read(key: 'user_role'); // Читаем сохраненную роль!

      // Выбираем эндпоинт в зависимости от роли
      final String endpoint = (role == 'LANDLORD')
          ? '/api/profiles/landlord/me'
          : '/api/profiles/tenant/me';

      final response = await _dio.get(
        endpoint,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        return UserProfile.fromJson(response.data);
      }
      return null;
    } on DioException catch (e) {
      // Расширенное логирование, чтобы точно видеть ошибку от сервера
      print('Ошибка API при загрузке профиля: ${e.response?.statusCode} - ${e.response?.data}');
      return null;
    } catch (e) {
      print('Неизвестная ошибка профиля: $e');
      return null;
    }
  }

  // Выход из аккаунта
  Future<void> logout() async {
    // Просто удаляем токены из защищенного хранилища
    await _storage.delete(key: 'jwt_token');
    await _storage.delete(key: 'user_role');
  }
  Future<bool> login(String email, String password, bool rememberMe) async {
    try {
      final response = await _dio.post('/api/auth/login', data: {
        'email': email,
        'password': password,
      });

      if (response.statusCode == 200) {
        final token = response.data['token'];
        final role = response.data['role'];

        await _storage.write(key: 'jwt_token', value: token);
        await _storage.write(key: 'user_role', value: role);

        // --- ЛОГИКА REMEMBER ME ---
        await _storage.write(key: 'remember_me', value: rememberMe.toString());
        if (rememberMe) {
          await _storage.write(key: 'saved_email', value: email);
        } else {
          await _storage.delete(key: 'saved_email');
        }

        return true;
      }
      return false;
    } catch (e) {
      print('Ошибка входа: $e');
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
  Future<String?> getSavedEmail() async {
    return await _storage.read(key: 'saved_email');
  }

  // Метод, который решает, куда отправить юзера при старте приложения
  Future<String?> checkAutoLogin() async {
    final rememberMe = await _storage.read(key: 'remember_me');

    // Если галочка стояла, проверяем токен
    if (rememberMe == 'true') {
      final token = await _storage.read(key: 'jwt_token');
      final role = await _storage.read(key: 'user_role');
      if (token != null && role != null) {
        return role; // Автологин успешен! Возвращаем роль
      }
    } else {
      // Если галочки не было, значит сессия была только на один раз. Стираем токен.
      await logout();
    }
    return null; // Нужна авторизация
  }
  Future<bool> updateProfile(String name, String phone, int? categoryId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final role = await _storage.read(key: 'user_role');

      final String endpoint = (role == 'LANDLORD')
          ? '/api/profiles/landlord/me'
          : '/api/profiles/tenant/me';

      final response = await _dio.put(
        endpoint,
        data: {
          if (role == 'LANDLORD') 'companyName': name else 'name': name,
          'phone': phone,
          // Отправляем ID категории на сервер (ожидаем, что бэк принимает targetBusinessCategoryId)
          if (role == 'TENANT' && categoryId != null) 'targetBusinessCategoryId': categoryId,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Ошибка при обновлении профиля: $e');
      return false;
    }
  }
}