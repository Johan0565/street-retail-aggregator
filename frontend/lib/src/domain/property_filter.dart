import 'property.dart';

enum ScoreBucket { low, medium, high }

extension ScoreBucketRange on ScoreBucket {
  int get min {
    switch (this) {
      case ScoreBucket.low:
        return 0;
      case ScoreBucket.medium:
        return 40;
      case ScoreBucket.high:
        return 80;
    }
  }

  int get max {
    switch (this) {
      case ScoreBucket.low:
        return 40;
      case ScoreBucket.medium:
        return 80;
      case ScoreBucket.high:
        return 1000;
    }
  }

  bool contains(int score) => score >= min && score < max;
}

class PropertyFilter {
  final double? minPrice;
  final double? maxPrice;
  final double? minArea;
  final double? maxArea;
  final String? metroStation;
  final Set<String> propertyTypes;
  final bool onlyFree;
  final Set<ScoreBucket> scoreBuckets;

  const PropertyFilter({
    this.minPrice,
    this.maxPrice,
    this.minArea,
    this.maxArea,
    this.metroStation,
    this.propertyTypes = const {},
    this.onlyFree = false,
    this.scoreBuckets = const {},
  });

  static const PropertyFilter empty = PropertyFilter();

  bool get isActive =>
      minPrice != null ||
      maxPrice != null ||
      minArea != null ||
      maxArea != null ||
      (metroStation?.isNotEmpty ?? false) ||
      propertyTypes.isNotEmpty ||
      onlyFree ||
      scoreBuckets.isNotEmpty;

  int get activeCount {
    int n = 0;
    if (minPrice != null || maxPrice != null) n++;
    if (minArea != null || maxArea != null) n++;
    if (metroStation?.isNotEmpty ?? false) n++;
    if (propertyTypes.isNotEmpty) n++;
    if (onlyFree) n++;
    if (scoreBuckets.isNotEmpty) n++;
    return n;
  }

  List<Property> apply(
    List<Property> properties, {
    int? Function(int propertyId)? scoreOf,
  }) {
    return properties.where((p) {
      if (minPrice != null && p.pricePerMonth < minPrice!) return false;
      if (maxPrice != null && p.pricePerMonth > maxPrice!) return false;
      if (minArea != null && p.areaSqm < minArea!) return false;
      if (maxArea != null && p.areaSqm > maxArea!) return false;
      if (metroStation != null && metroStation!.isNotEmpty) {
        final metro = p.metroStation?.toLowerCase() ?? '';
        if (!metro.contains(metroStation!.toLowerCase())) return false;
      }
      if (propertyTypes.isNotEmpty) {
        if (p.propertyType == null || !propertyTypes.contains(p.propertyType)) {
          return false;
        }
      }
      if (onlyFree && (p.isOccupied ?? false)) return false;
      if (scoreBuckets.isNotEmpty) {
        if (scoreOf == null) return false;
        final score = scoreOf(p.id);
        if (score == null) return false;
        final hit = scoreBuckets.any((b) => b.contains(score));
        if (!hit) return false;
      }
      return true;
    }).toList();
  }
}
