import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AnalyticsDto {
  final int totalViewsLast30Days;
  final int totalApplications;
  final int totalFavorites;
  final Map<String, int> viewsByDate;

  AnalyticsDto({
    required this.totalViewsLast30Days,
    required this.totalApplications,
    required this.totalFavorites,
    required this.viewsByDate,
  });

  factory AnalyticsDto.fromJson(Map<String, dynamic> json) {
    return AnalyticsDto(
      totalViewsLast30Days: (json['totalViewsLast30Days'] as num?)?.toInt() ?? 0,
      totalApplications: (json['totalApplications'] as num?)?.toInt() ?? 0,
      totalFavorites: (json['totalFavorites'] as num?)?.toInt() ?? 0,
      viewsByDate: (json['viewsByDate'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      ) ?? {},
    );
  }
}

class AnalyticsService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'http://10.0.2.2:8080',
    headers: {'Content-Type': 'application/json'},
  ));
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<AnalyticsDto> getMyAnalytics() async {
    final token = await _storage.read(key: 'jwt_token');
    final response = await _dio.get(
      '/api/analytics/my-properties',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return AnalyticsDto.fromJson(response.data);
  }

  Future<void> logPropertyView(int propertyId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      await _dio.post(
        '/api/analytics/view/$propertyId',
        options: token != null ? Options(headers: {'Authorization': 'Bearer $token'}) : null,
      );
    } catch (e) {
      // Ignore errors for analytics logging
    }
  }
}
