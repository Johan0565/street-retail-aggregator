import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

import '../config/api_config.dart';
import '../domain/saved_account.dart';
import '../domain/user_profile.dart';


class AuthService {
  static const _kSavedAccounts = 'saved_accounts';
  static const _kActiveEmail = 'active_account_email';

  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
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
        final profile = UserProfile.fromJson(response.data);
        // Подтягиваем имя в сохранённый аккаунт, если оно появилось/обновилось
        await _refreshActiveAccountName(profile.name);
        return profile;
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

  // Завершение активной сессии. Аккаунт остаётся в списке сохранённых,
  // чтобы пользователь мог быстро переключиться обратно.
  Future<void> logout() async {
    await _storage.delete(key: 'jwt_token');
    await _storage.delete(key: 'user_role');
    await _storage.delete(key: _kActiveEmail);
  }
  Future<bool> login(String email, String password, bool rememberMe) async {
    try {
      final response = await _dio.post('/api/auth/login', data: {
        'email': email,
        'password': password,
      });

      if (response.statusCode == 200) {
        final token = response.data['token'] as String;
        final role = response.data['role'] as String;

        await _activateSession(email: email, token: token, role: role);

        // --- ЛОГИКА REMEMBER ME ---
        await _storage.write(key: 'remember_me', value: rememberMe.toString());
        if (rememberMe) {
          await _storage.write(key: 'saved_email', value: email);
          await _upsertSavedAccount(SavedAccount(
            email: email,
            role: role,
            token: token,
            lastUsedAt: DateTime.now(),
          ));
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
        final token = response.data['token'] as String;
        final role = response.data['role'] as String;
        await _activateSession(email: cleanEmail, token: token, role: role);
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
      if (token != null && role != null && !_isTokenExpired(token)) {
        return role; // Автологин успешен! Возвращаем роль
      }
    } else {
      // Если галочки не было, значит сессия была только на один раз. Стираем токен.
      await logout();
    }
    return null; // Нужна авторизация
  }
  /// Загружает новую аватарку. Возвращает относительный URL вида /uploads/avatars/...
  /// либо null при ошибке.
  Future<String?> uploadAvatar(File file) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: file.uri.pathSegments.last),
      });
      final response = await _dio.post(
        '/api/profiles/me/avatar',
        data: form,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      if (response.statusCode == 200 && response.data is Map) {
        return (response.data as Map)['avatarUrl']?.toString();
      }
      return null;
    } catch (e) {
      print('Ошибка загрузки аватара: $e');
      return null;
    }
  }

  Future<bool> deleteAvatar() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.delete(
        '/api/profiles/me/avatar',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      return false;
    }
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

      if (response.statusCode == 200) {
        await _refreshActiveAccountName(name);
        return true;
      }
      return false;
    } catch (e) {
      print('Ошибка при обновлении профиля: $e');
      return false;
    }
  }

  // ===== Мульти-аккаунт =====

  Future<List<SavedAccount>> getSavedAccounts() async {
    final raw = await _storage.read(key: _kSavedAccounts);
    final list = SavedAccount.decodeList(raw);
    list.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    return list;
  }

  Future<String?> getActiveEmail() async {
    return await _storage.read(key: _kActiveEmail);
  }

  // Пробует продолжить сессию для уже сохранённого аккаунта.
  // Возвращает роль при успехе, иначе null (например, токен протух).
  Future<String?> resumeSavedAccount(String email) async {
    final accounts = await getSavedAccounts();
    final match = accounts
        .where((a) => a.email.toLowerCase() == email.toLowerCase())
        .toList();
    if (match.isEmpty) return null;
    final account = match.first;
    if (_isTokenExpired(account.token)) {
      return null;
    }
    await _activateSession(
      email: account.email,
      token: account.token,
      role: account.role,
    );
    await _storage.write(key: 'remember_me', value: 'true');
    await _storage.write(key: 'saved_email', value: account.email);
    await _upsertSavedAccount(account.copyWith(lastUsedAt: DateTime.now()));
    return account.role;
  }

  Future<void> removeSavedAccount(String email) async {
    final accounts = await getSavedAccounts();
    accounts.removeWhere((a) => a.email.toLowerCase() == email.toLowerCase());
    await _storage.write(
      key: _kSavedAccounts,
      value: SavedAccount.encodeList(accounts),
    );
    final activeEmail = await _storage.read(key: _kActiveEmail);
    if (activeEmail != null && activeEmail.toLowerCase() == email.toLowerCase()) {
      await logout();
    }
    final savedEmail = await _storage.read(key: 'saved_email');
    if (savedEmail != null && savedEmail.toLowerCase() == email.toLowerCase()) {
      await _storage.delete(key: 'saved_email');
    }
  }

  Future<void> _activateSession({
    required String email,
    required String token,
    required String role,
  }) async {
    await _storage.write(key: 'jwt_token', value: token);
    await _storage.write(key: 'user_role', value: role);
    await _storage.write(key: _kActiveEmail, value: email);
  }

  Future<void> _upsertSavedAccount(SavedAccount account) async {
    final accounts = await getSavedAccounts();
    final idx = accounts.indexWhere(
      (a) => a.email.toLowerCase() == account.email.toLowerCase(),
    );
    if (idx >= 0) {
      accounts[idx] = account.copyWith(
        displayName: account.displayName ?? accounts[idx].displayName,
      );
    } else {
      accounts.add(account);
    }
    await _storage.write(
      key: _kSavedAccounts,
      value: SavedAccount.encodeList(accounts),
    );
  }

  Future<void> _refreshActiveAccountName(String? name) async {
    if (name == null || name.trim().isEmpty) return;
    final activeEmail = await _storage.read(key: _kActiveEmail);
    if (activeEmail == null) return;
    final accounts = await getSavedAccounts();
    final idx = accounts.indexWhere(
      (a) => a.email.toLowerCase() == activeEmail.toLowerCase(),
    );
    if (idx < 0) return;
    accounts[idx] = accounts[idx].copyWith(displayName: name.trim());
    await _storage.write(
      key: _kSavedAccounts,
      value: SavedAccount.encodeList(accounts),
    );
  }

  bool _isTokenExpired(String token) {
    try {
      return JwtDecoder.isExpired(token);
    } catch (_) {
      // Если токен невалидный/нечитаемый — считаем его непригодным.
      return true;
    }
  }
}
