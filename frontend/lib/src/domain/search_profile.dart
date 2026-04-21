import 'package:flutter/material.dart';

import 'property.dart';

/// Dart-модель «Проект поиска арендатора» — зеркало SearchProfile на бэкенде.
class SearchProfile {
  final int id;
  final String name;

  // Категория бизнеса
  final int? businessCategoryId;
  final String? businessCategoryName;

  // Финансовые критерии
  final double? minArea;
  final double? maxArea;
  final double? minBudget;
  final double? maxBudget;

  // Технические критерии
  final int? minPowerKw;
  final bool? requiresWater;
  final bool? requiresVentilation;
  final bool? requiresSeparateEntrance;

  // Локация
  final double? centerLatitude;
  final double? centerLongitude;
  final int? searchRadiusMeters;

  final bool isActive;
  final String? createdAt;

  const SearchProfile({
    required this.id,
    required this.name,
    this.businessCategoryId,
    this.businessCategoryName,
    this.minArea,
    this.maxArea,
    this.minBudget,
    this.maxBudget,
    this.minPowerKw,
    this.requiresWater,
    this.requiresVentilation,
    this.requiresSeparateEntrance,
    this.centerLatitude,
    this.centerLongitude,
    this.searchRadiusMeters,
    this.isActive = true,
    this.createdAt,
  });

  factory SearchProfile.fromJson(Map<String, dynamic> json) {
    return SearchProfile(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? 'Без названия',
      businessCategoryId: json['businessCategory'] != null
          ? (json['businessCategory']['id'] as num?)?.toInt()
          : null,
      businessCategoryName: json['businessCategory'] != null
          ? json['businessCategory']['name']?.toString()
          : null,
      minArea: (json['minArea'] as num?)?.toDouble(),
      maxArea: (json['maxArea'] as num?)?.toDouble(),
      minBudget: (json['minBudget'] as num?)?.toDouble(),
      maxBudget: (json['maxBudget'] as num?)?.toDouble(),
      minPowerKw: (json['minPowerKw'] as num?)?.toInt(),
      requiresWater: json['requiresWater'] as bool?,
      requiresVentilation: json['requiresVentilation'] as bool?,
      requiresSeparateEntrance: json['requiresSeparateEntrance'] as bool?,
      centerLatitude: (json['centerLatitude'] as num?)?.toDouble(),
      centerLongitude: (json['centerLongitude'] as num?)?.toDouble(),
      searchRadiusMeters: (json['searchRadiusMeters'] as num?)?.toInt(),
      isActive: json['isActive'] as bool? ?? true,
      createdAt: json['createdAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (businessCategoryId != null) 'businessCategoryId': businessCategoryId,
        if (minArea != null) 'minArea': minArea,
        if (maxArea != null) 'maxArea': maxArea,
        if (minBudget != null) 'minBudget': minBudget,
        if (maxBudget != null) 'maxBudget': maxBudget,
        if (minPowerKw != null) 'minPowerKw': minPowerKw,
        if (requiresWater != null) 'requiresWater': requiresWater,
        if (requiresVentilation != null) 'requiresVentilation': requiresVentilation,
        if (requiresSeparateEntrance != null) 'requiresSeparateEntrance': requiresSeparateEntrance,
        if (centerLatitude != null) 'centerLatitude': centerLatitude,
        if (centerLongitude != null) 'centerLongitude': centerLongitude,
        if (searchRadiusMeters != null) 'searchRadiusMeters': searchRadiusMeters,
      };
}

/// Dart-модель помещения с результатом скоринга.
class ScoredProperty {
  final Property property;
  final int totalScore;       // 0-100
  final int financialScore;   // 0-20
  final int technicalScore;   // 0-40
  final int locationScore;    // 0-25
  final int competitorScore;  // 0-15
  final String matchLabel;
  final String matchColor;    // "green", "yellow", "red"

  const ScoredProperty({
    required this.property,
    required this.totalScore,
    required this.financialScore,
    required this.technicalScore,
    required this.locationScore,
    required this.competitorScore,
    required this.matchLabel,
    required this.matchColor,
  });

  factory ScoredProperty.fromJson(Map<String, dynamic> json) {
    return ScoredProperty(
      property: Property.fromJson(json['property'] as Map<String, dynamic>),
      totalScore: (json['totalScore'] as num?)?.toInt() ?? 0,
      financialScore: (json['financialScore'] as num?)?.toInt() ?? 0,
      technicalScore: (json['technicalScore'] as num?)?.toInt() ?? 0,
      locationScore: (json['locationScore'] as num?)?.toInt() ?? 0,
      competitorScore: (json['competitorScore'] as num?)?.toInt() ?? 0,
      matchLabel: json['matchLabel']?.toString() ?? '',
      matchColor: json['matchColor']?.toString() ?? 'red',
    );
  }

  /// Flutter Color по строковому значению matchColor из бэкенда
  Color get flutterColor {
    switch (matchColor) {
      case 'green':
        return const Color(0xFF22C55E);
      case 'yellow':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFFEF4444);
    }
  }

  /// Иконка для маркера на карте
  String get markerEmoji {
    if (totalScore >= 75) return '🔥';
    if (totalScore >= 50) return '👍';
    if (totalScore >= 25) return '⚠️';
    return '❌';
  }
}
