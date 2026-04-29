import 'property.dart';

class PropertyFilter {
  final double? minPrice;
  final double? maxPrice;
  final double? minArea;
  final double? maxArea;
  final String? metroStation;
  final Set<String> propertyTypes;
  final bool onlyFree;

  const PropertyFilter({
    this.minPrice,
    this.maxPrice,
    this.minArea,
    this.maxArea,
    this.metroStation,
    this.propertyTypes = const {},
    this.onlyFree = false,
  });

  static const PropertyFilter empty = PropertyFilter();

  bool get isActive =>
      minPrice != null ||
      maxPrice != null ||
      minArea != null ||
      maxArea != null ||
      (metroStation?.isNotEmpty ?? false) ||
      propertyTypes.isNotEmpty ||
      onlyFree;

  int get activeCount {
    int n = 0;
    if (minPrice != null || maxPrice != null) n++;
    if (minArea != null || maxArea != null) n++;
    if (metroStation?.isNotEmpty ?? false) n++;
    if (propertyTypes.isNotEmpty) n++;
    if (onlyFree) n++;
    return n;
  }

  List<Property> apply(List<Property> properties) {
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
      return true;
    }).toList();
  }
}
