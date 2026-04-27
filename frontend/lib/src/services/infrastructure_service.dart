import 'package:dio/dio.dart';

class PoiDto {
  final String name;
  final String category;
  final double distanceMeters;
  final bool isCompetitor;

  PoiDto({
    required this.name,
    required this.category,
    required this.distanceMeters,
    this.isCompetitor = false,
  });

  factory PoiDto.fromJson(Map<String, dynamic> json) {
    return PoiDto(
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0.0,
      isCompetitor: json['isCompetitor'] as bool? ?? false,
    );
  }
}

class InfrastructureService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'http://10.0.2.2:8080',
    headers: {'Content-Type': 'application/json'},
  ));

  Future<List<PoiDto>> getInfrastructureNearby(double lat, double lon, {int? profileId}) async {
    final response = await _dio.get(
      '/api/infrastructure',
      queryParameters: {
        'lat': lat,
        'lon': lon,
        'radius': 500,
        if (profileId != null) 'profileId': profileId,
      },
    );
    return (response.data as List).map((e) => PoiDto.fromJson(e)).toList();
  }
}
