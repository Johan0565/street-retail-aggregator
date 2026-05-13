import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/api_config.dart';

class PoiDto {
  final String name;
  final String category;
  final double distanceMeters;

  PoiDto({
    required this.name,
    required this.category,
    required this.distanceMeters,
  });

  factory PoiDto.fromJson(Map<String, dynamic> json) {
    return PoiDto(
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class InfrastructureService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Dio get _dio => Dio(BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));

  Future<List<PoiDto>> getInfrastructureNearby(double lat, double lon) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final response = await _dio.get(
        '/api/infrastructure',
        queryParameters: {'lat': lat, 'lon': lon, 'radius': 500},
        options: token != null
            ? Options(headers: {'Authorization': 'Bearer $token'})
            : null,
      );
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((e) => PoiDto.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
