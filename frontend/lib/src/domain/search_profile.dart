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
  final bool? requiresWc;
  final bool? requiresParking;
  final bool? requiresLoadingZone;
  final double? minCeilingHeight;

  // Локация
  final double? centerLatitude;
  final double? centerLongitude;
  final int? searchRadiusMeters;
  /// Отдельный радиус для поиска синергичных соседей. Если null —
  /// используется searchRadiusMeters (старые проекты).
  final int? synergyRadiusMeters;

  // Желаемые соседи (категории для синергии)
  final List<int> desiredNeighborCategoryIds;
  final List<String> desiredNeighborNames;

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
    this.requiresWc,
    this.requiresParking,
    this.requiresLoadingZone,
    this.minCeilingHeight,
    this.centerLatitude,
    this.centerLongitude,
    this.searchRadiusMeters,
    this.synergyRadiusMeters,
    this.desiredNeighborCategoryIds = const [],
    this.desiredNeighborNames = const [],
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
      requiresWc: json['requiresWc'] as bool?,
      requiresParking: json['requiresParking'] as bool?,
      requiresLoadingZone: json['requiresLoadingZone'] as bool?,
      minCeilingHeight: (json['minCeilingHeight'] as num?)?.toDouble(),
      centerLatitude: (json['centerLatitude'] as num?)?.toDouble(),
      centerLongitude: (json['centerLongitude'] as num?)?.toDouble(),
      searchRadiusMeters: (json['searchRadiusMeters'] as num?)?.toInt(),
      synergyRadiusMeters: (json['synergyRadiusMeters'] as num?)?.toInt(),
      desiredNeighborCategoryIds: (json['desiredNeighbors'] is List)
          ? (json['desiredNeighbors'] as List)
              .map((e) => (e is Map ? (e['id'] as num?)?.toInt() : null))
              .whereType<int>()
              .toList()
          : const [],
      desiredNeighborNames: (json['desiredNeighbors'] is List)
          ? (json['desiredNeighbors'] as List)
              .map((e) => (e is Map ? e['name']?.toString() : null))
              .whereType<String>()
              .toList()
          : const [],
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
        if (requiresWc != null) 'requiresWc': requiresWc,
        if (requiresParking != null) 'requiresParking': requiresParking,
        if (requiresLoadingZone != null) 'requiresLoadingZone': requiresLoadingZone,
        if (minCeilingHeight != null) 'minCeilingHeight': minCeilingHeight,
        if (centerLatitude != null) 'centerLatitude': centerLatitude,
        if (centerLongitude != null) 'centerLongitude': centerLongitude,
        if (searchRadiusMeters != null) 'searchRadiusMeters': searchRadiusMeters,
        if (synergyRadiusMeters != null) 'synergyRadiusMeters': synergyRadiusMeters,
        if (desiredNeighborCategoryIds.isNotEmpty)
          'desiredNeighborCategoryIds': desiredNeighborCategoryIds,
      };
}

/// Dart-модель помещения с результатом скоринга.
class ScoredProperty {
  final Property property;
  final int totalScore;       // 0-100
  final int financialScore;   // 0-20 (площадь + бюджет, асимметричный smooth decay)
  final int technicalScore;   // 0-20 (тех. требования, градиент + null-discount)
  final int competitorScore;  // 0-40 (конкуренты, distance-weighted exp decay)
  final int synergyScore;     // 0-15 (синергия с желаемыми соседями, distance-aware)
  final int transportScore;   // 0-5  (близость общественного транспорта)
  final List<String> directCompetitorNames;
  final List<String> indirectCompetitorNames;
  final List<String> synergyNeighborNames;
  final String matchLabel;
  final String matchColor;    // "green", "yellow", "red"
  final ScoreBreakdown? breakdown;

  const ScoredProperty({
    required this.property,
    required this.totalScore,
    required this.financialScore,
    required this.technicalScore,
    required this.competitorScore,
    required this.synergyScore,
    required this.transportScore,
    required this.matchLabel,
    required this.matchColor,
    this.directCompetitorNames = const [],
    this.indirectCompetitorNames = const [],
    this.synergyNeighborNames = const [],
    this.breakdown,
  });

  factory ScoredProperty.fromJson(Map<String, dynamic> json) {
    List<String> parseStringList(dynamic v) => v is List
        ? v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList()
        : const [];

    return ScoredProperty(
      property: Property.fromJson(json['property'] as Map<String, dynamic>),
      totalScore: (json['totalScore'] as num?)?.toInt() ?? 0,
      financialScore: (json['financialScore'] as num?)?.toInt() ?? 0,
      technicalScore: (json['technicalScore'] as num?)?.toInt() ?? 0,
      competitorScore: (json['competitorScore'] as num?)?.toInt() ?? 0,
      synergyScore: (json['synergyScore'] as num?)?.toInt() ?? 0,
      transportScore: (json['transportScore'] as num?)?.toInt() ?? 0,
      directCompetitorNames: parseStringList(json['directCompetitorNames']),
      indirectCompetitorNames: parseStringList(json['indirectCompetitorNames']),
      synergyNeighborNames: parseStringList(json['synergyNeighborNames']),
      matchLabel: json['matchLabel']?.toString() ?? '',
      matchColor: json['matchColor']?.toString() ?? 'red',
      breakdown: json['breakdown'] is Map<String, dynamic>
          ? ScoreBreakdown.fromJson(json['breakdown'] as Map<String, dynamic>)
          : null,
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

/// Структурированная разбивка скоринга, приходит с бэкенда. Позволяет UI
/// показать tooltip «почему такой балл» без обращения к LLM. Все поля
/// опциональны — старые версии бэкенда могут не присылать breakdown.
class ScoreBreakdown {
  final FinancialPart? financial;
  final TechnicalPart? technical;
  final CompetitorPart? competitor;
  final SynergyPart? synergy;
  final TransportPart? transport;

  const ScoreBreakdown({this.financial, this.technical, this.competitor, this.synergy, this.transport});

  factory ScoreBreakdown.fromJson(Map<String, dynamic> json) => ScoreBreakdown(
        financial: json['financial'] is Map<String, dynamic>
            ? FinancialPart.fromJson(json['financial'] as Map<String, dynamic>) : null,
        technical: json['technical'] is Map<String, dynamic>
            ? TechnicalPart.fromJson(json['technical'] as Map<String, dynamic>) : null,
        competitor: json['competitor'] is Map<String, dynamic>
            ? CompetitorPart.fromJson(json['competitor'] as Map<String, dynamic>) : null,
        synergy: json['synergy'] is Map<String, dynamic>
            ? SynergyPart.fromJson(json['synergy'] as Map<String, dynamic>) : null,
        transport: json['transport'] is Map<String, dynamic>
            ? TransportPart.fromJson(json['transport'] as Map<String, dynamic>) : null,
      );
}

class FinancialPart {
  final double budgetPoints;
  final String? budgetReason;
  final double areaPoints;
  final String? areaReason;
  const FinancialPart({required this.budgetPoints, this.budgetReason, required this.areaPoints, this.areaReason});
  factory FinancialPart.fromJson(Map<String, dynamic> j) => FinancialPart(
        budgetPoints: (j['budgetPoints'] as num?)?.toDouble() ?? 0,
        budgetReason: j['budgetReason']?.toString(),
        areaPoints: (j['areaPoints'] as num?)?.toDouble() ?? 0,
        areaReason: j['areaReason']?.toString(),
      );
}

class TechnicalPart {
  final List<TechnicalItem> items;
  const TechnicalPart({this.items = const []});
  factory TechnicalPart.fromJson(Map<String, dynamic> j) => TechnicalPart(
        items: (j['items'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(TechnicalItem.fromJson)
                .toList() ??
            const [],
      );
}

class TechnicalItem {
  final String requirement;
  final double penalty;
  final String? reason;
  const TechnicalItem({required this.requirement, required this.penalty, this.reason});
  factory TechnicalItem.fromJson(Map<String, dynamic> j) => TechnicalItem(
        requirement: j['requirement']?.toString() ?? '',
        penalty: (j['penalty'] as num?)?.toDouble() ?? 0,
        reason: j['reason']?.toString(),
      );
}

class CompetitorPart {
  final double weightedDirect;
  final double weightedIndirect;
  final List<CompetitorRef> directRefs;
  final List<CompetitorRef> indirectRefs;
  final int totalNearbyBusinesses;
  final int radiusMeters;
  const CompetitorPart({
    this.weightedDirect = 0,
    this.weightedIndirect = 0,
    this.directRefs = const [],
    this.indirectRefs = const [],
    this.totalNearbyBusinesses = 0,
    this.radiusMeters = 0,
  });
  factory CompetitorPart.fromJson(Map<String, dynamic> j) => CompetitorPart(
        weightedDirect: (j['weightedDirect'] as num?)?.toDouble() ?? 0,
        weightedIndirect: (j['weightedIndirect'] as num?)?.toDouble() ?? 0,
        directRefs: (j['directRefs'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(CompetitorRef.fromJson)
                .toList() ??
            const [],
        indirectRefs: (j['indirectRefs'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(CompetitorRef.fromJson)
                .toList() ??
            const [],
        totalNearbyBusinesses: (j['totalNearbyBusinesses'] as num?)?.toInt() ?? 0,
        radiusMeters: (j['radiusMeters'] as num?)?.toInt() ?? 0,
      );
}

class CompetitorRef {
  final String name;
  final double distanceMeters;
  final double weight;
  final double? latitude;
  final double? longitude;
  /// Влияние этого конкурента на competitorScore. Обычно отрицательное
  /// (отнимает баллы); 0 если у бизнеса нулевой вес.
  final double scoreImpact;
  const CompetitorRef({
    required this.name,
    required this.distanceMeters,
    required this.weight,
    this.latitude,
    this.longitude,
    this.scoreImpact = 0,
  });
  factory CompetitorRef.fromJson(Map<String, dynamic> j) => CompetitorRef(
        name: j['name']?.toString() ?? '',
        distanceMeters: (j['distanceMeters'] as num?)?.toDouble() ?? -1,
        weight: (j['weight'] as num?)?.toDouble() ?? 0,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        scoreImpact: (j['scoreImpact'] as num?)?.toDouble() ?? 0,
      );
}

class SynergyPart {
  final int desiredCategoriesCount;
  final int foundCategoriesCount;
  final List<SynergyRef> refs;
  const SynergyPart({this.desiredCategoriesCount = 0, this.foundCategoriesCount = 0, this.refs = const []});
  factory SynergyPart.fromJson(Map<String, dynamic> j) => SynergyPart(
        desiredCategoriesCount: (j['desiredCategoriesCount'] as num?)?.toInt() ?? 0,
        foundCategoriesCount: (j['foundCategoriesCount'] as num?)?.toInt() ?? 0,
        refs: (j['refs'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(SynergyRef.fromJson)
                .toList() ??
            const [],
      );
}

class SynergyRef {
  final String name;
  final double distanceMeters;
  final double weight;
  final double? latitude;
  final double? longitude;
  /// Сколько баллов этот сосед добавил в synergyScore. 0, если он не
  /// выиграл ни одной категории (показан в списке для информации).
  final double scoreImpact;
  const SynergyRef({
    required this.name,
    required this.distanceMeters,
    required this.weight,
    this.latitude,
    this.longitude,
    this.scoreImpact = 0,
  });
  factory SynergyRef.fromJson(Map<String, dynamic> j) => SynergyRef(
        name: j['name']?.toString() ?? '',
        distanceMeters: (j['distanceMeters'] as num?)?.toDouble() ?? -1,
        weight: (j['weight'] as num?)?.toDouble() ?? 0,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        scoreImpact: (j['scoreImpact'] as num?)?.toDouble() ?? 0,
      );
}

class TransportPart {
  final String? nearestName;
  final String nearestType;       // METRO / RAIL / TRAM / BUS / NONE
  final double nearestDistanceMeters; // -1 = ничего не найдено
  final String? reason;
  const TransportPart({this.nearestName, this.nearestType = 'NONE', this.nearestDistanceMeters = -1, this.reason});
  factory TransportPart.fromJson(Map<String, dynamic> j) => TransportPart(
        nearestName: j['nearestName']?.toString(),
        nearestType: j['nearestType']?.toString() ?? 'NONE',
        nearestDistanceMeters: (j['nearestDistanceMeters'] as num?)?.toDouble() ?? -1,
        reason: j['reason']?.toString(),
      );

  /// Локализованное имя типа транспорта для UI.
  String get typeLabel => switch (nearestType) {
        'METRO' => 'метро',
        'RAIL'  => 'ж/д',
        'TRAM'  => 'трамвай',
        'BUS'   => 'автобус',
        _       => 'нет общественного транспорта',
      };
}
