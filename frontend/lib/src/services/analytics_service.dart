import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/api_config.dart';

class AnalyticsDto {
  final int totalViewsLast30Days;
  final int totalFavoritesLast30Days;
  final int totalApplications;
  final int totalApplicationsLast30Days;
  final int totalUniqueMessengers;
  final Map<String, int> viewsByDate;
  final Map<String, int> favoritesByDate;
  final Map<String, int> applicationsByDate;
  final int? propertyId;
  final String? propertyTitle;

  AnalyticsDto({
    required this.totalViewsLast30Days,
    required this.totalFavoritesLast30Days,
    required this.totalApplications,
    required this.totalApplicationsLast30Days,
    required this.totalUniqueMessengers,
    required this.viewsByDate,
    required this.favoritesByDate,
    required this.applicationsByDate,
    this.propertyId,
    this.propertyTitle,
  });

  factory AnalyticsDto.fromJson(Map<String, dynamic> json) {
    Map<String, int> readMap(String key) {
      final raw = json[key];
      if (raw is Map) {
        return raw.map((k, v) =>
            MapEntry(k.toString(), (v as num?)?.toInt() ?? 0));
      }
      return <String, int>{};
    }

    return AnalyticsDto(
      totalViewsLast30Days:
          (json['totalViewsLast30Days'] as num?)?.toInt() ?? 0,
      totalFavoritesLast30Days:
          (json['totalFavoritesLast30Days'] as num?)?.toInt() ?? 0,
      totalApplications: (json['totalApplications'] as num?)?.toInt() ?? 0,
      totalApplicationsLast30Days:
          (json['totalApplicationsLast30Days'] as num?)?.toInt() ?? 0,
      totalUniqueMessengers:
          (json['totalUniqueMessengers'] as num?)?.toInt() ?? 0,
      viewsByDate: readMap('viewsByDate'),
      favoritesByDate: readMap('favoritesByDate'),
      applicationsByDate: readMap('applicationsByDate'),
      propertyId: (json['propertyId'] as num?)?.toInt(),
      propertyTitle: json['propertyTitle']?.toString(),
    );
  }
}

class AnalyticsService {
  Dio get _dio => Dio(BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<AnalyticsDto?> getMyAnalytics() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '/api/analytics/my-properties',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return AnalyticsDto.fromJson(response.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<AnalyticsDto?> getPropertyAnalytics(int propertyId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '/api/analytics/property/$propertyId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return AnalyticsDto.fromJson(response.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> logPropertyView(int propertyId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      await _dio.post(
        '/api/analytics/view/$propertyId',
        options: token != null
            ? Options(headers: {'Authorization': 'Bearer $token'})
            : null,
      );
    } catch (_) {
    }
    await ViewedPropertiesStore.instance.add(propertyId);
  }
}

/// Локальный персистентный список помещений, которые арендатор уже открывал
/// в деталях. Используется только для UI-подсказки на карте — чтобы метки
/// просмотренных помещений выводились слегка серовато-оранжевым цветом.
/// Хранится в FlutterSecureStorage как строка с запятыми (значения compactны
/// и легко парсятся без зависимости от dart:convert).
class ViewedPropertiesStore {
  ViewedPropertiesStore._();
  static final ViewedPropertiesStore instance = ViewedPropertiesStore._();

  static const String _storageKey = 'viewed_property_ids';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  Set<int>? _cache;

  Future<Set<int>> load() async {
    if (_cache != null) return _cache!;
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) {
      _cache = <int>{};
      return _cache!;
    }
    final ids = <int>{};
    for (final part in raw.split(',')) {
      final id = int.tryParse(part.trim());
      if (id != null) ids.add(id);
    }
    _cache = ids;
    return _cache!;
  }

  Future<void> add(int propertyId) async {
    final ids = await load();
    if (ids.add(propertyId)) {
      await _storage.write(key: _storageKey, value: ids.join(','));
    }
  }

  bool isViewedSync(int propertyId) {
    return _cache?.contains(propertyId) ?? false;
  }
}
