import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../../../domain/property.dart';
import '../../../domain/property_filter.dart';
import '../../../domain/search_profile.dart';
import '../../../services/property_service.dart';
import '../../../services/search_profile_service.dart';
import 'property_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

class MapScreen extends StatefulWidget {
  final bool isLandlordMode;
  const MapScreen({super.key, this.isLandlordMode = false});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  late YandexMapController mapController;
  final PropertyService _propertyService = PropertyService();
  final SearchProfileService _scoringService = SearchProfileService();

  List<MapObject> mapObjects = [];
  bool _isLoading = false;

  // Скоринг
  List<SearchProfile> _myProfiles = [];
  SearchProfile? _activeProfile;
  // Кэш: propertyId -> ScoredProperty (для bottomSheet)
  Map<int, ScoredProperty> _scoreCache = {};
  List<Property> _allProperties = [];
  PropertyFilter _activeFilter = PropertyFilter.empty;

  // Поиск адреса
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<SuggestItem> _searchSuggestions = [];
  bool _isSearchingAddress = false;
  bool _mapControllerReady = false;

  final Color _primaryOrange = const Color(0xFFFF8C00);

  // ВАЖНО: Вставь сюда свой длинный JSON со стилями карты между тройными кавычками!
  final String _mapStyle = '''[
{
  "tags": "country",
  "elements": "geometry.fill",
  "stylers": [
    {
      "color": "#8c8c8c"
    },
    {
      "zoom": 0,
      "opacity": 0.8
    },
    {
      "zoom": 1,
      "opacity": 0.8
    },
    {
      "zoom": 2,
      "opacity": 0.8
    },
    {
      "zoom": 3,
      "opacity": 0.8
    },
    {
      "zoom": 4,
      "opacity": 0.8
    },
    {
      "zoom": 5,
      "opacity": 1
    },
    {
      "zoom": 6,
      "opacity": 1
    },
    {
      "zoom": 7,
      "opacity": 1
    },
    {
      "zoom": 8,
      "opacity": 1
    },
    {
      "zoom": 9,
      "opacity": 1
    },
    {
      "zoom": 10,
      "opacity": 1
    },
    {
      "zoom": 11,
      "opacity": 1
    },
    {
      "zoom": 12,
      "opacity": 1
    },
    {
      "zoom": 13,
      "opacity": 1
    },
    {
      "zoom": 14,
      "opacity": 1
    },
    {
      "zoom": 15,
      "opacity": 1
    },
    {
      "zoom": 16,
      "opacity": 1
    },
    {
      "zoom": 17,
      "opacity": 1
    },
    {
      "zoom": 18,
      "opacity": 1
    },
    {
      "zoom": 19,
      "opacity": 1
    },
    {
      "zoom": 20,
      "opacity": 1
    },
    {
      "zoom": 21,
      "opacity": 1
    }
  ]
},
{
"tags": "country",
"elements": "geometry.outline",
"stylers": [
{
"color": "#dedede"
},
{
"zoom": 0,
"opacity": 0.15
},
{
"zoom": 1,
"opacity": 0.15
},
{
"zoom": 2,
"opacity": 0.15
},
{
"zoom": 3,
"opacity": 0.15
},
{
"zoom": 4,
"opacity": 0.15
},
{
"zoom": 5,
"opacity": 0.15
},
{
"zoom": 6,
"opacity": 0.25
},
{
"zoom": 7,
"opacity": 0.5
},
{
"zoom": 8,
"opacity": 0.47
},
{
"zoom": 9,
"opacity": 0.44
},
{
"zoom": 10,
"opacity": 0.41
},
{
"zoom": 11,
"opacity": 0.38
},
{
"zoom": 12,
"opacity": 0.35
},
{
"zoom": 13,
"opacity": 0.33
},
{
"zoom": 14,
"opacity": 0.3
},
{
"zoom": 15,
"opacity": 0.28
},
{
"zoom": 16,
"opacity": 0.25
},
{
"zoom": 17,
"opacity": 0.25
},
{
"zoom": 18,
"opacity": 0.25
},
{
"zoom": 19,
"opacity": 0.25
},
{
"zoom": 20,
"opacity": 0.25
},
{
"zoom": 21,
"opacity": 0.25
}
]
},
{
"tags": "region",
"elements": "geometry.fill",
"stylers": [
{
"zoom": 0,
"color": "#a6a6a6",
"opacity": 0.5
},
{
"zoom": 1,
"color": "#a6a6a6",
"opacity": 0.5
},
{
"zoom": 2,
"color": "#a6a6a6",
"opacity": 0.5
},
{
"zoom": 3,
"color": "#a6a6a6",
"opacity": 0.5
},
{
"zoom": 4,
"color": "#a6a6a6",
"opacity": 0.5
},
{
"zoom": 5,
"color": "#a6a6a6",
"opacity": 0.5
},
{
"zoom": 6,
"color": "#a6a6a6",
"opacity": 1
},
{
"zoom": 7,
"color": "#a6a6a6",
"opacity": 1
},
{
"zoom": 8,
"color": "#8c8c8c",
"opacity": 1
},
{
"zoom": 9,
"color": "#8c8c8c",
"opacity": 1
},
{
"zoom": 10,
"color": "#8c8c8c",
"opacity": 1
},
{
"zoom": 11,
"color": "#8c8c8c",
"opacity": 1
},
{
"zoom": 12,
"color": "#8c8c8c",
"opacity": 1
},
{
"zoom": 13,
"color": "#8c8c8c",
"opacity": 1
},
{
"zoom": 14,
"color": "#8c8c8c",
"opacity": 1
},
{
"zoom": 15,
"color": "#8c8c8c",
"opacity": 1
},
{
"zoom": 16,
"color": "#8c8c8c",
"opacity": 1
},
{
"zoom": 17,
"color": "#8c8c8c",
"opacity": 1
},
{
"zoom": 18,
"color": "#8c8c8c",
"opacity": 1
},
{
"zoom": 19,
"color": "#8c8c8c",
"opacity": 1
},
{
"zoom": 20,
"color": "#8c8c8c",
"opacity": 1
},
{
"zoom": 21,
"color": "#8c8c8c",
"opacity": 1
}
]
},
{
"tags": "region",
"elements": "geometry.outline",
"stylers": [
{
"color": "#dedede"
},
{
"zoom": 0,
"opacity": 0.15
},
{
"zoom": 1,
"opacity": 0.15
},
{
"zoom": 2,
"opacity": 0.15
},
{
"zoom": 3,
"opacity": 0.15
},
{
"zoom": 4,
"opacity": 0.15
},
{
"zoom": 5,
"opacity": 0.15
},
{
"zoom": 6,
"opacity": 0.25
},
{
"zoom": 7,
"opacity": 0.5
},
{
"zoom": 8,
"opacity": 0.47
},
{
"zoom": 9,
"opacity": 0.44
},
{
"zoom": 10,
"opacity": 0.41
},
{
"zoom": 11,
"opacity": 0.38
},
{
"zoom": 12,
"opacity": 0.35
},
{
"zoom": 13,
"opacity": 0.33
},
{
"zoom": 14,
"opacity": 0.3
},
{
"zoom": 15,
"opacity": 0.28
},
{
"zoom": 16,
"opacity": 0.25
},
{
"zoom": 17,
"opacity": 0.25
},
{
"zoom": 18,
"opacity": 0.25
},
{
"zoom": 19,
"opacity": 0.25
},
{
"zoom": 20,
"opacity": 0.25
},
{
"zoom": 21,
"opacity": 0.25
}
]
},
{
"tags": {
"any": "admin",
"none": [
"country",
"region",
"locality",
"district",
"address"
]
},
"elements": "geometry.fill",
"stylers": [
{
"color": "#8c8c8c"
},
{
"zoom": 0,
"opacity": 0.5
},
{
"zoom": 1,
"opacity": 0.5
},
{
"zoom": 2,
"opacity": 0.5
},
{
"zoom": 3,
"opacity": 0.5
},
{
"zoom": 4,
"opacity": 0.5
},
{
"zoom": 5,
"opacity": 0.5
},
{
"zoom": 6,
"opacity": 1
},
{
"zoom": 7,
"opacity": 1
},
{
"zoom": 8,
"opacity": 1
},
{
"zoom": 9,
"opacity": 1
},
{
"zoom": 10,
"opacity": 1
},
{
"zoom": 11,
"opacity": 1
},
{
"zoom": 12,
"opacity": 1
},
{
"zoom": 13,
"opacity": 1
},
{
"zoom": 14,
"opacity": 1
},
{
"zoom": 15,
"opacity": 1
},
{
"zoom": 16,
"opacity": 1
},
{
"zoom": 17,
"opacity": 1
},
{
"zoom": 18,
"opacity": 1
},
{
"zoom": 19,
"opacity": 1
},
{
"zoom": 20,
"opacity": 1
},
{
"zoom": 21,
"opacity": 1
}
]
},
{
"tags": {
"any": "admin",
"none": [
"country",
"region",
"locality",
"district",
"address"
]
},
"elements": "geometry.outline",
"stylers": [
{
"color": "#dedede"
},
{
"zoom": 0,
"opacity": 0.15
},
{
"zoom": 1,
"opacity": 0.15
},
{
"zoom": 2,
"opacity": 0.15
},
{
"zoom": 3,
"opacity": 0.15
},
{
"zoom": 4,
"opacity": 0.15
},
{
"zoom": 5,
"opacity": 0.15
},
{
"zoom": 6,
"opacity": 0.25
},
{
"zoom": 7,
"opacity": 0.5
},
{
"zoom": 8,
"opacity": 0.47
},
{
"zoom": 9,
"opacity": 0.44
},
{
"zoom": 10,
"opacity": 0.41
},
{
"zoom": 11,
"opacity": 0.38
},
{
"zoom": 12,
"opacity": 0.35
},
{
"zoom": 13,
"opacity": 0.33
},
{
"zoom": 14,
"opacity": 0.3
},
{
"zoom": 15,
"opacity": 0.28
},
{
"zoom": 16,
"opacity": 0.25
},
{
"zoom": 17,
"opacity": 0.25
},
{
"zoom": 18,
"opacity": 0.25
},
{
"zoom": 19,
"opacity": 0.25
},
{
"zoom": 20,
"opacity": 0.25
},
{
"zoom": 21,
"opacity": 0.25
}
]
},
{
"tags": {
"any": "landcover",
"none": "vegetation"
},
"stylers": [
{
"hue": "#c7cfd6"
}
]
},
{
"tags": "vegetation",
"elements": "geometry",
"stylers": [
{
"zoom": 0,
"color": "#aab6c0",
"opacity": 0.1
},
{
"zoom": 1,
"color": "#aab6c0",
"opacity": 0.1
},
{
"zoom": 2,
"color": "#aab6c0",
"opacity": 0.1
},
{
"zoom": 3,
"color": "#aab6c0",
"opacity": 0.1
},
{
"zoom": 4,
"color": "#aab6c0",
"opacity": 0.1
},
{
"zoom": 5,
"color": "#aab6c0",
"opacity": 0.1
},
{
"zoom": 6,
"color": "#aab6c0",
"opacity": 0.2
},
{
"zoom": 7,
"color": "#c7cfd6",
"opacity": 0.3
},
{
"zoom": 8,
"color": "#c7cfd6",
"opacity": 0.4
},
{
"zoom": 9,
"color": "#c7cfd6",
"opacity": 0.6
},
{
"zoom": 10,
"color": "#c7cfd6",
"opacity": 0.8
},
{
"zoom": 11,
"color": "#c7cfd6",
"opacity": 1
},
{
"zoom": 12,
"color": "#c7cfd6",
"opacity": 1
},
{
"zoom": 13,
"color": "#c7cfd6",
"opacity": 1
},
{
"zoom": 14,
"color": "#cdd4da",
"opacity": 1
},
{
"zoom": 15,
"color": "#d3d9df",
"opacity": 1
},
{
"zoom": 16,
"color": "#d3d9df",
"opacity": 1
},
{
"zoom": 17,
"color": "#d3d9df",
"opacity": 1
},
{
"zoom": 18,
"color": "#d3d9df",
"opacity": 1
},
{
"zoom": 19,
"color": "#d3d9df",
"opacity": 1
},
{
"zoom": 20,
"color": "#d3d9df",
"opacity": 1
},
{
"zoom": 21,
"color": "#d3d9df",
"opacity": 1
}
]
},
{
"tags": "park",
"elements": "geometry",
"stylers": [
{
"zoom": 0,
"color": "#c7cfd6",
"opacity": 0.1
},
{
"zoom": 1,
"color": "#c7cfd6",
"opacity": 0.1
},
{
"zoom": 2,
"color": "#c7cfd6",
"opacity": 0.1
},
{
"zoom": 3,
"color": "#c7cfd6",
"opacity": 0.1
},
{
"zoom": 4,
"color": "#c7cfd6",
"opacity": 0.1
},
{
"zoom": 5,
"color": "#c7cfd6",
"opacity": 0.1
},
{
"zoom": 6,
"color": "#c7cfd6",
"opacity": 0.2
},
{
"zoom": 7,
"color": "#c7cfd6",
"opacity": 0.3
},
{
"zoom": 8,
"color": "#c7cfd6",
"opacity": 0.4
},
{
"zoom": 9,
"color": "#c7cfd6",
"opacity": 0.6
},
{
"zoom": 10,
"color": "#c7cfd6",
"opacity": 0.8
},
{
"zoom": 11,
"color": "#c7cfd6",
"opacity": 1
},
{
"zoom": 12,
"color": "#c7cfd6",
"opacity": 1
},
{
"zoom": 13,
"color": "#c7cfd6",
"opacity": 1
},
{
"zoom": 14,
"color": "#cdd4da",
"opacity": 1
},
{
"zoom": 15,
"color": "#d3d9df",
"opacity": 1
},
{
"zoom": 16,
"color": "#d3d9df",
"opacity": 0.9
},
{
"zoom": 17,
"color": "#d3d9df",
"opacity": 0.8
},
{
"zoom": 18,
"color": "#d3d9df",
"opacity": 0.7
},
{
"zoom": 19,
"color": "#d3d9df",
"opacity": 0.7
},
{
"zoom": 20,
"color": "#d3d9df",
"opacity": 0.7
},
{
"zoom": 21,
"color": "#d3d9df",
"opacity": 0.7
}
]
},
{
"tags": "national_park",
"elements": "geometry",
"stylers": [
{
"zoom": 0,
"color": "#c7cfd6",
"opacity": 0.1
},
{
"zoom": 1,
"color": "#c7cfd6",
"opacity": 0.1
},
{
"zoom": 2,
"color": "#c7cfd6",
"opacity": 0.1
},
{
"zoom": 3,
"color": "#c7cfd6",
"opacity": 0.1
},
{
"zoom": 4,
"color": "#c7cfd6",
"opacity": 0.1
},
{
"zoom": 5,
"color": "#c7cfd6",
"opacity": 0.1
},
{
"zoom": 6,
"color": "#c7cfd6",
"opacity": 0.2
},
{
"zoom": 7,
"color": "#c7cfd6",
"opacity": 0.3
},
{
"zoom": 8,
"color": "#c7cfd6",
"opacity": 0.4
},
{
"zoom": 9,
"color": "#c7cfd6",
"opacity": 0.6
},
{
"zoom": 10,
"color": "#c7cfd6",
"opacity": 0.8
},
{
"zoom": 11,
"color": "#c7cfd6",
"opacity": 1
},
{
"zoom": 12,
"color": "#c7cfd6",
"opacity": 1
},
{
"zoom": 13,
"color": "#c7cfd6",
"opacity": 1
},
{
"zoom": 14,
"color": "#cdd4da",
"opacity": 1
},
{
"zoom": 15,
"color": "#d3d9df",
"opacity": 1
},
{
"zoom": 16,
"color": "#d3d9df",
"opacity": 0.7
},
{
"zoom": 17,
"color": "#d3d9df",
"opacity": 0.7
},
{
"zoom": 18,
"color": "#d3d9df",
"opacity": 0.7
},
{
"zoom": 19,
"color": "#d3d9df",
"opacity": 0.7
},
{
"zoom": 20,
"color": "#d3d9df",
"opacity": 0.7
},
{
"zoom": 21,
"color": "#d3d9df",
"opacity": 0.7
}
]
},
{
"tags": "cemetery",
"elements": "geometry",
"stylers": [
{
"zoom": 0,
"color": "#c7cfd6"
},
{
"zoom": 1,
"color": "#c7cfd6"
},
{
"zoom": 2,
"color": "#c7cfd6"
},
{
"zoom": 3,
"color": "#c7cfd6"
},
{
"zoom": 4,
"color": "#c7cfd6"
},
{
"zoom": 5,
"color": "#c7cfd6"
},
{
"zoom": 6,
"color": "#c7cfd6"
},
{
"zoom": 7,
"color": "#c7cfd6"
},
{
"zoom": 8,
"color": "#c7cfd6"
},
{
"zoom": 9,
"color": "#c7cfd6"
},
{
"zoom": 10,
"color": "#c7cfd6"
},
{
"zoom": 11,
"color": "#c7cfd6"
},
{
"zoom": 12,
"color": "#c7cfd6"
},
{
"zoom": 13,
"color": "#c7cfd6"
},
{
"zoom": 14,
"color": "#cdd4da"
},
{
"zoom": 15,
"color": "#d3d9df"
},
{
"zoom": 16,
"color": "#d3d9df"
},
{
"zoom": 17,
"color": "#d3d9df"
},
{
"zoom": 18,
"color": "#d3d9df"
},
{
"zoom": 19,
"color": "#d3d9df"
},
{
"zoom": 20,
"color": "#d3d9df"
},
{
"zoom": 21,
"color": "#d3d9df"
}
]
},
{
"tags": "sports_ground",
"elements": "geometry",
"stylers": [
{
"zoom": 0,
"color": "#b8c2cb",
"opacity": 0
},
{
"zoom": 1,
"color": "#b8c2cb",
"opacity": 0
},
{
"zoom": 2,
"color": "#b8c2cb",
"opacity": 0
},
{
"zoom": 3,
"color": "#b8c2cb",
"opacity": 0
},
{
"zoom": 4,
"color": "#b8c2cb",
"opacity": 0
},
{
"zoom": 5,
"color": "#b8c2cb",
"opacity": 0
},
{
"zoom": 6,
"color": "#b8c2cb",
"opacity": 0
},
{
"zoom": 7,
"color": "#b8c2cb",
"opacity": 0
},
{
"zoom": 8,
"color": "#b8c2cb",
"opacity": 0
},
{
"zoom": 9,
"color": "#b8c2cb",
"opacity": 0
},
{
"zoom": 10,
"color": "#b8c2cb",
"opacity": 0
},
{
"zoom": 11,
"color": "#b8c2cb",
"opacity": 0
},
{
"zoom": 12,
"color": "#b8c2cb",
"opacity": 0
},
{
"zoom": 13,
"color": "#b8c2cb",
"opacity": 0
},
{
"zoom": 14,
"color": "#bec7cf",
"opacity": 0
},
{
"zoom": 15,
"color": "#c4ccd4",
"opacity": 0.5
},
{
"zoom": 16,
"color": "#c5cdd5",
"opacity": 1
},
{
"zoom": 17,
"color": "#c6ced5",
"opacity": 1
},
{
"zoom": 18,
"color": "#c7ced6",
"opacity": 1
},
{
"zoom": 19,
"color": "#c8cfd7",
"opacity": 1
},
{
"zoom": 20,
"color": "#c9d0d7",
"opacity": 1
},
{
"zoom": 21,
"color": "#cad1d8",
"opacity": 1
}
]
},
{
"tags": "terrain",
"elements": "geometry",
"stylers": [
{
"hue": "#e1e3e5"
},
{
"zoom": 0,
"opacity": 0.3
},
{
"zoom": 1,
"opacity": 0.3
},
{
"zoom": 2,
"opacity": 0.3
},
{
"zoom": 3,
"opacity": 0.3
},
{
"zoom": 4,
"opacity": 0.3
},
{
"zoom": 5,
"opacity": 0.35
},
{
"zoom": 6,
"opacity": 0.4
},
{
"zoom": 7,
"opacity": 0.6
},
{
"zoom": 8,
"opacity": 0.8
},
{
"zoom": 9,
"opacity": 0.9
},
{
"zoom": 10,
"opacity": 1
},
{
"zoom": 11,
"opacity": 1
},
{
"zoom": 12,
"opacity": 1
},
{
"zoom": 13,
"opacity": 1
},
{
"zoom": 14,
"opacity": 1
},
{
"zoom": 15,
"opacity": 1
},
{
"zoom": 16,
"opacity": 1
},
{
"zoom": 17,
"opacity": 1
},
{
"zoom": 18,
"opacity": 1
},
{
"zoom": 19,
"opacity": 1
},
{
"zoom": 20,
"opacity": 1
},
{
"zoom": 21,
"opacity": 1
}
]
},
{
"tags": "geographic_line",
"elements": "geometry",
"stylers": [
{
"color": "#747d86"
}
]
},
{
"tags": "land",
"elements": "geometry",
"stylers": [
{
"zoom": 0,
"color": "#e1e3e4"
},
{
"zoom": 1,
"color": "#e1e3e4"
},
{
"zoom": 2,
"color": "#e1e3e4"
},
{
"zoom": 3,
"color": "#e1e3e4"
},
{
"zoom": 4,
"color": "#e1e3e4"
},
{
"zoom": 5,
"color": "#e4e5e6"
},
{
"zoom": 6,
"color": "#e6e8e9"
},
{
"zoom": 7,
"color": "#e9eaeb"
},
{
"zoom": 8,
"color": "#ecedee"
},
{
"zoom": 9,
"color": "#ecedee"
},
{
"zoom": 10,
"color": "#ecedee"
},
{
"zoom": 11,
"color": "#ecedee"
},
{
"zoom": 12,
"color": "#ecedee"
},
{
"zoom": 13,
"color": "#ecedee"
},
{
"zoom": 14,
"color": "#eeeff0"
},
{
"zoom": 15,
"color": "#f1f2f3"
},
{
"zoom": 16,
"color": "#f1f2f3"
},
{
"zoom": 17,
"color": "#f2f3f4"
},
{
"zoom": 18,
"color": "#f2f3f4"
},
{
"zoom": 19,
"color": "#f3f4f4"
},
{
"zoom": 20,
"color": "#f3f4f5"
},
{
"zoom": 21,
"color": "#f4f5f5"
}
]
},
{
"tags": "residential",
"elements": "geometry",
"stylers": [
{
"zoom": 0,
"color": "#e1e3e5",
"opacity": 0.5
},
{
"zoom": 1,
"color": "#e1e3e5",
"opacity": 0.5
},
{
"zoom": 2,
"color": "#e1e3e5",
"opacity": 0.5
},
{
"zoom": 3,
"color": "#e1e3e5",
"opacity": 0.5
},
{
"zoom": 4,
"color": "#e1e3e5",
"opacity": 0.5
},
{
"zoom": 5,
"color": "#e1e3e5",
"opacity": 0.5
},
{
"zoom": 6,
"color": "#e1e3e5",
"opacity": 0.5
},
{
"zoom": 7,
"color": "#e1e3e5",
"opacity": 0.5
},
{
"zoom": 8,
"color": "#e1e3e5",
"opacity": 0.5
},
{
"zoom": 9,
"color": "#e1e3e5",
"opacity": 0.5
},
{
"zoom": 10,
"color": "#e1e3e5",
"opacity": 0.5
},
{
"zoom": 11,
"color": "#e1e3e5",
"opacity": 0.5
},
{
"zoom": 12,
"color": "#e1e3e5",
"opacity": 0.5
},
{
"zoom": 13,
"color": "#e1e3e5",
"opacity": 1
},
{
"zoom": 14,
"color": "#e6e8e9",
"opacity": 1
},
{
"zoom": 15,
"color": "#ecedee",
"opacity": 1
},
{
"zoom": 16,
"color": "#edeeef",
"opacity": 1
},
{
"zoom": 17,
"color": "#eeeff0",
"opacity": 1
},
{
"zoom": 18,
"color": "#eeeff0",
"opacity": 1
},
{
"zoom": 19,
"color": "#eff0f1",
"opacity": 1
},
{
"zoom": 20,
"color": "#f0f1f2",
"opacity": 1
},
{
"zoom": 21,
"color": "#f1f2f3",
"opacity": 1
}
]
},
{
"tags": "locality",
"elements": "geometry",
"stylers": [
{
"zoom": 0,
"color": "#e1e3e5"
},
{
"zoom": 1,
"color": "#e1e3e5"
},
{
"zoom": 2,
"color": "#e1e3e5"
},
{
"zoom": 3,
"color": "#e1e3e5"
},
{
"zoom": 4,
"color": "#e1e3e5"
},
{
"zoom": 5,
"color": "#e1e3e5"
},
{
"zoom": 6,
"color": "#e1e3e5"
},
{
"zoom": 7,
"color": "#e1e3e5"
},
{
"zoom": 8,
"color": "#e1e3e5"
},
{
"zoom": 9,
"color": "#e1e3e5"
},
{
"zoom": 10,
"color": "#e1e3e5"
},
{
"zoom": 11,
"color": "#e1e3e5"
},
{
"zoom": 12,
"color": "#e1e3e5"
},
{
"zoom": 13,
"color": "#e1e3e5"
},
{
"zoom": 14,
"color": "#e6e8e9"
},
{
"zoom": 15,
"color": "#ecedee"
},
{
"zoom": 16,
"color": "#edeeef"
},
{
"zoom": 17,
"color": "#eeeff0"
},
{
"zoom": 18,
"color": "#eeeff0"
},
{
"zoom": 19,
"color": "#eff0f1"
},
{
"zoom": 20,
"color": "#f0f1f2"
},
{
"zoom": 21,
"color": "#f1f2f3"
}
]
},
{
"tags": {
"any": "structure",
"none": [
"building",
"fence"
]
},
"elements": "geometry",
"stylers": [
{
"opacity": 0.9
},
{
"zoom": 0,
"color": "#e1e3e5"
},
{
"zoom": 1,
"color": "#e1e3e5"
},
{
"zoom": 2,
"color": "#e1e3e5"
},
{
"zoom": 3,
"color": "#e1e3e5"
},
{
"zoom": 4,
"color": "#e1e3e5"
},
{
"zoom": 5,
"color": "#e1e3e5"
},
{
"zoom": 6,
"color": "#e1e3e5"
},
{
"zoom": 7,
"color": "#e1e3e5"
},
{
"zoom": 8,
"color": "#e1e3e5"
},
{
"zoom": 9,
"color": "#e1e3e5"
},
{
"zoom": 10,
"color": "#e1e3e5"
},
{
"zoom": 11,
"color": "#e1e3e5"
},
{
"zoom": 12,
"color": "#e1e3e5"
},
{
"zoom": 13,
"color": "#e1e3e5"
},
{
"zoom": 14,
"color": "#e6e8e9"
},
{
"zoom": 15,
"color": "#ecedee"
},
{
"zoom": 16,
"color": "#edeeef"
},
{
"zoom": 17,
"color": "#eeeff0"
},
{
"zoom": 18,
"color": "#eeeff0"
},
{
"zoom": 19,
"color": "#eff0f1"
},
{
"zoom": 20,
"color": "#f0f1f2"
},
{
"zoom": 21,
"color": "#f1f2f3"
}
]
},
{
"tags": "building",
"elements": "geometry.fill",
"stylers": [
{
"color": "#dee0e3"
},
{
"zoom": 0,
"opacity": 0.7
},
{
"zoom": 1,
"opacity": 0.7
},
{
"zoom": 2,
"opacity": 0.7
},
{
"zoom": 3,
"opacity": 0.7
},
{
"zoom": 4,
"opacity": 0.7
},
{
"zoom": 5,
"opacity": 0.7
},
{
"zoom": 6,
"opacity": 0.7
},
{
"zoom": 7,
"opacity": 0.7
},
{
"zoom": 8,
"opacity": 0.7
},
{
"zoom": 9,
"opacity": 0.7
},
{
"zoom": 10,
"opacity": 0.7
},
{
"zoom": 11,
"opacity": 0.7
},
{
"zoom": 12,
"opacity": 0.7
},
{
"zoom": 13,
"opacity": 0.7
},
{
"zoom": 14,
"opacity": 0.7
},
{
"zoom": 15,
"opacity": 0.7
},
{
"zoom": 16,
"opacity": 0.9
},
{
"zoom": 17,
"opacity": 0.6
},
{
"zoom": 18,
"opacity": 0.6
},
{
"zoom": 19,
"opacity": 0.6
},
{
"zoom": 20,
"opacity": 0.6
},
{
"zoom": 21,
"opacity": 0.6
}
]
},
{
"tags": "building",
"elements": "geometry.outline",
"stylers": [
{
"color": "#c8ccd1"
},
{
"zoom": 0,
"opacity": 0.5
},
{
"zoom": 1,
"opacity": 0.5
},
{
"zoom": 2,
"opacity": 0.5
},
{
"zoom": 3,
"opacity": 0.5
},
{
"zoom": 4,
"opacity": 0.5
},
{
"zoom": 5,
"opacity": 0.5
},
{
"zoom": 6,
"opacity": 0.5
},
{
"zoom": 7,
"opacity": 0.5
},
{
"zoom": 8,
"opacity": 0.5
},
{
"zoom": 9,
"opacity": 0.5
},
{
"zoom": 10,
"opacity": 0.5
},
{
"zoom": 11,
"opacity": 0.5
},
{
"zoom": 12,
"opacity": 0.5
},
{
"zoom": 13,
"opacity": 0.5
},
{
"zoom": 14,
"opacity": 0.5
},
{
"zoom": 15,
"opacity": 0.5
},
{
"zoom": 16,
"opacity": 0.5
},
{
"zoom": 17,
"opacity": 1
},
{
"zoom": 18,
"opacity": 1
},
{
"zoom": 19,
"opacity": 1
},
{
"zoom": 20,
"opacity": 1
},
{
"zoom": 21,
"opacity": 1
}
]
},
{
"tags": {
"any": "urban_area",
"none": [
"residential",
"industrial",
"cemetery",
"park",
"medical",
"sports_ground",
"beach",
"construction_site"
]
},
"elements": "geometry",
"stylers": [
{
"zoom": 0,
"color": "#d6d9dc",
"opacity": 1
},
{
"zoom": 1,
"color": "#d6d9dc",
"opacity": 1
},
{
"zoom": 2,
"color": "#d6d9dc",
"opacity": 1
},
{
"zoom": 3,
"color": "#d6d9dc",
"opacity": 1
},
{
"zoom": 4,
"color": "#d6d9dc",
"opacity": 1
},
{
"zoom": 5,
"color": "#d6d9dc",
"opacity": 1
},
{
"zoom": 6,
"color": "#d6d9dc",
"opacity": 1
},
{
"zoom": 7,
"color": "#d6d9dc",
"opacity": 1
},
{
"zoom": 8,
"color": "#d6d9dc",
"opacity": 1
},
{
"zoom": 9,
"color": "#d6d9dc",
"opacity": 1
},
{
"zoom": 10,
"color": "#d6d9dc",
"opacity": 1
},
{
"zoom": 11,
"color": "#d6d9dc",
"opacity": 1
},
{
"zoom": 12,
"color": "#d6d9dc",
"opacity": 1
},
{
"zoom": 13,
"color": "#d6d9dc",
"opacity": 1
},
{
"zoom": 14,
"color": "#dddfe2",
"opacity": 1
},
{
"zoom": 15,
"color": "#e4e6e8",
"opacity": 1
},
{
"zoom": 16,
"color": "#ebeced",
"opacity": 0.67
},
{
"zoom": 17,
"color": "#f2f3f3",
"opacity": 0.33
},
{
"zoom": 18,
"color": "#f2f3f3",
"opacity": 0
},
{
"zoom": 19,
"color": "#f2f3f3",
"opacity": 0
},
{
"zoom": 20,
"color": "#f2f3f3",
"opacity": 0
},
{
"zoom": 21,
"color": "#f2f3f3",
"opacity": 0
}
]
},
{
"tags": "poi",
"elements": "label.icon",
"stylers": [
{
"color": "#9da6af"
},
{
"secondary-color": "#ffffff"
},
{
"tertiary-color": "#ffffff"
}
]
},
{
"tags": "poi",
"elements": "label.text.fill",
"stylers": [
{
"color": "#778088"
}
]
},
{
"tags": "poi",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": "outdoor",
"elements": "label.icon",
"stylers": [
{
"color": "#9da6af"
},
{
"secondary-color": "#ffffff"
},
{
"tertiary-color": "#ffffff"
}
]
},
{
"tags": "outdoor",
"elements": "label.text.fill",
"stylers": [
{
"color": "#778088"
}
]
},
{
"tags": "outdoor",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": "park",
"elements": "label.icon",
"stylers": [
{
"color": "#9da6af"
},
{
"secondary-color": "#ffffff"
},
{
"tertiary-color": "#ffffff"
}
]
},
{
"tags": "park",
"elements": "label.text.fill",
"stylers": [
{
"color": "#778088"
}
]
},
{
"tags": "park",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": "cemetery",
"elements": "label.icon",
"stylers": [
{
"color": "#9da6af"
},
{
"secondary-color": "#ffffff"
},
{
"tertiary-color": "#ffffff"
}
]
},
{
"tags": "cemetery",
"elements": "label.text.fill",
"stylers": [
{
"color": "#778088"
}
]
},
{
"tags": "cemetery",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": "beach",
"elements": "label.icon",
"stylers": [
{
"color": "#9da6af"
},
{
"secondary-color": "#ffffff"
},
{
"tertiary-color": "#ffffff"
}
]
},
{
"tags": "beach",
"elements": "label.text.fill",
"stylers": [
{
"color": "#778088"
}
]
},
{
"tags": "beach",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": "medical",
"elements": "label.icon",
"stylers": [
{
"color": "#9da6af"
},
{
"secondary-color": "#ffffff"
},
{
"tertiary-color": "#ffffff"
}
]
},
{
"tags": "medical",
"elements": "label.text.fill",
"stylers": [
{
"color": "#778088"
}
]
},
{
"tags": "medical",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": "shopping",
"elements": "label.icon",
"stylers": [
{
"color": "#9da6af"
},
{
"secondary-color": "#ffffff"
},
{
"tertiary-color": "#ffffff"
}
]
},
{
"tags": "shopping",
"elements": "label.text.fill",
"stylers": [
{
"color": "#778088"
}
]
},
{
"tags": "shopping",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": "commercial_services",
"elements": "label.icon",
"stylers": [
{
"color": "#9da6af"
},
{
"secondary-color": "#ffffff"
},
{
"tertiary-color": "#ffffff"
}
]
},
{
"tags": "commercial_services",
"elements": "label.text.fill",
"stylers": [
{
"color": "#778088"
}
]
},
{
"tags": "commercial_services",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": "food_and_drink",
"elements": "label.icon",
"stylers": [
{
"color": "#9da6af"
},
{
"secondary-color": "#ffffff"
},
{
"tertiary-color": "#ffffff"
}
]
},
{
"tags": "food_and_drink",
"elements": "label.text.fill",
"stylers": [
{
"color": "#778088"
}
]
},
{
"tags": "food_and_drink",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": "road",
"elements": "label.icon",
"types": "point",
"stylers": [
{
"color": "#9da6af"
},
{
"secondary-color": "#ffffff"
},
{
"tertiary-color": "#ffffff"
}
]
},
{
"tags": "road",
"elements": "label.text.fill",
"types": "point",
"stylers": [
{
"color": "#ffffff"
}
]
},
{
"tags": "entrance",
"elements": "label.icon",
"stylers": [
{
"color": "#9da6af"
},
{
"secondary-color": "#ffffff"
}
]
},
{
"tags": "locality",
"elements": "label.icon",
"stylers": [
{
"color": "#9da6af"
},
{
"secondary-color": "#ffffff"
}
]
},
{
"tags": "country",
"elements": "label.text.fill",
"stylers": [
{
"opacity": 0.8
},
{
"color": "#8f969e"
}
]
},
{
"tags": "country",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": "region",
"elements": "label.text.fill",
"stylers": [
{
"color": "#8f969e"
},
{
"opacity": 0.8
}
]
},
{
"tags": "region",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": "district",
"elements": "label.text.fill",
"stylers": [
{
"color": "#8f969e"
},
{
"opacity": 0.8
}
]
},
{
"tags": "district",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": {
"any": "admin",
"none": [
"country",
"region",
"locality",
"district",
"address"
]
},
"elements": "label.text.fill",
"stylers": [
{
"color": "#8f969e"
}
]
},
{
"tags": {
"any": "admin",
"none": [
"country",
"region",
"locality",
"district",
"address"
]
},
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": "locality",
"elements": "label.text.fill",
"stylers": [
{
"zoom": 0,
"color": "#778088"
},
{
"zoom": 1,
"color": "#778088"
},
{
"zoom": 2,
"color": "#778088"
},
{
"zoom": 3,
"color": "#778088"
},
{
"zoom": 4,
"color": "#778088"
},
{
"zoom": 5,
"color": "#757e86"
},
{
"zoom": 6,
"color": "#737c83"
},
{
"zoom": 7,
"color": "#717a81"
},
{
"zoom": 8,
"color": "#6f777f"
},
{
"zoom": 9,
"color": "#6d757c"
},
{
"zoom": 10,
"color": "#6b737a"
},
{
"zoom": 11,
"color": "#6b737a"
},
{
"zoom": 12,
"color": "#6b737a"
},
{
"zoom": 13,
"color": "#6b737a"
},
{
"zoom": 14,
"color": "#6b737a"
},
{
"zoom": 15,
"color": "#6b737a"
},
{
"zoom": 16,
"color": "#6b737a"
},
{
"zoom": 17,
"color": "#6b737a"
},
{
"zoom": 18,
"color": "#6b737a"
},
{
"zoom": 19,
"color": "#6b737a"
},
{
"zoom": 20,
"color": "#6b737a"
},
{
"zoom": 21,
"color": "#6b737a"
}
]
},
{
"tags": "locality",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": "road",
"elements": "label.text.fill",
"types": "polyline",
"stylers": [
{
"color": "#778088"
}
]
},
{
"tags": "road",
"elements": "label.text.outline",
"types": "polyline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": "road",
"elements": "geometry.fill.pattern",
"types": "polyline",
"stylers": [
{
"scale": 1
},
{
"color": "#adb3b8"
}
]
},
{
"tags": "road",
"elements": "label.text.fill",
"types": "point",
"stylers": [
{
"color": "#ffffff"
}
]
},
{
"tags": "structure",
"elements": "label.text.fill",
"stylers": [
{
"color": "#5f666d"
},
{
"opacity": 0.5
}
]
},
{
"tags": "structure",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": "entrance",
"elements": "label.text.fill",
"stylers": [
{
"color": "#5f666d"
},
{
"opacity": 1
}
]
},
{
"tags": "entrance",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": "address",
"elements": "label.text.fill",
"stylers": [
{
"color": "#5f666d"
},
{
"zoom": 0,
"opacity": 0.9
},
{
"zoom": 1,
"opacity": 0.9
},
{
"zoom": 2,
"opacity": 0.9
},
{
"zoom": 3,
"opacity": 0.9
},
{
"zoom": 4,
"opacity": 0.9
},
{
"zoom": 5,
"opacity": 0.9
},
{
"zoom": 6,
"opacity": 0.9
},
{
"zoom": 7,
"opacity": 0.9
},
{
"zoom": 8,
"opacity": 0.9
},
{
"zoom": 9,
"opacity": 0.9
},
{
"zoom": 10,
"opacity": 0.9
},
{
"zoom": 11,
"opacity": 0.9
},
{
"zoom": 12,
"opacity": 0.9
},
{
"zoom": 13,
"opacity": 0.9
},
{
"zoom": 14,
"opacity": 0.9
},
{
"zoom": 15,
"opacity": 0.9
},
{
"zoom": 16,
"opacity": 0.9
},
{
"zoom": 17,
"opacity": 1
},
{
"zoom": 18,
"opacity": 1
},
{
"zoom": 19,
"opacity": 1
},
{
"zoom": 20,
"opacity": 1
},
{
"zoom": 21,
"opacity": 1
}
]
},
{
"tags": "address",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.5
}
]
},
{
"tags": "landscape",
"elements": "label.text.fill",
"stylers": [
{
"zoom": 0,
"color": "#8f969e",
"opacity": 1
},
{
"zoom": 1,
"color": "#8f969e",
"opacity": 1
},
{
"zoom": 2,
"color": "#8f969e",
"opacity": 1
},
{
"zoom": 3,
"color": "#8f969e",
"opacity": 1
},
{
"zoom": 4,
"color": "#5f666d",
"opacity": 0.5
},
{
"zoom": 5,
"color": "#5f666d",
"opacity": 0.5
},
{
"zoom": 6,
"color": "#5f666d",
"opacity": 0.5
},
{
"zoom": 7,
"color": "#5f666d",
"opacity": 0.5
},
{
"zoom": 8,
"color": "#5f666d",
"opacity": 0.5
},
{
"zoom": 9,
"color": "#5f666d",
"opacity": 0.5
},
{
"zoom": 10,
"color": "#5f666d",
"opacity": 0.5
},
{
"zoom": 11,
"color": "#5f666d",
"opacity": 0.5
},
{
"zoom": 12,
"color": "#5f666d",
"opacity": 0.5
},
{
"zoom": 13,
"color": "#5f666d",
"opacity": 0.5
},
{
"zoom": 14,
"color": "#5f666d",
"opacity": 0.5
},
{
"zoom": 15,
"color": "#5f666d",
"opacity": 0.5
},
{
"zoom": 16,
"color": "#5f666d",
"opacity": 0.5
},
{
"zoom": 17,
"color": "#5f666d",
"opacity": 0.5
},
{
"zoom": 18,
"color": "#5f666d",
"opacity": 0.5
},
{
"zoom": 19,
"color": "#5f666d",
"opacity": 0.5
},
{
"zoom": 20,
"color": "#5f666d",
"opacity": 0.5
},
{
"zoom": 21,
"color": "#5f666d",
"opacity": 0.5
}
]
},
{
"tags": "landscape",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
},
{
"zoom": 0,
"opacity": 0.5
},
{
"zoom": 1,
"opacity": 0.5
},
{
"zoom": 2,
"opacity": 0.5
},
{
"zoom": 3,
"opacity": 0.5
},
{
"zoom": 4,
"opacity": 0
},
{
"zoom": 5,
"opacity": 0
},
{
"zoom": 6,
"opacity": 0
},
{
"zoom": 7,
"opacity": 0
},
{
"zoom": 8,
"opacity": 0
},
{
"zoom": 9,
"opacity": 0
},
{
"zoom": 10,
"opacity": 0
},
{
"zoom": 11,
"opacity": 0
},
{
"zoom": 12,
"opacity": 0
},
{
"zoom": 13,
"opacity": 0
},
{
"zoom": 14,
"opacity": 0
},
{
"zoom": 15,
"opacity": 0
},
{
"zoom": 16,
"opacity": 0
},
{
"zoom": 17,
"opacity": 0
},
{
"zoom": 18,
"opacity": 0
},
{
"zoom": 19,
"opacity": 0
},
{
"zoom": 20,
"opacity": 0
},
{
"zoom": 21,
"opacity": 0
}
]
},
{
"tags": "water",
"elements": "label.text.fill",
"stylers": [
{
"color": "#5e6871"
},
{
"opacity": 0.8
}
]
},
{
"tags": "water",
"elements": "label.text.outline",
"types": "polyline",
"stylers": [
{
"color": "#ffffff"
},
{
"opacity": 0.2
}
]
},
{
"tags": {
"any": "road_1",
"none": "is_tunnel"
},
"elements": "geometry.fill",
"stylers": [
{
"color": "#ffffff"
},
{
"zoom": 0,
"scale": 0
},
{
"zoom": 1,
"scale": 0
},
{
"zoom": 2,
"scale": 0
},
{
"zoom": 3,
"scale": 0
},
{
"zoom": 4,
"scale": 0
},
{
"zoom": 5,
"scale": 0
},
{
"zoom": 6,
"scale": 3.3
},
{
"zoom": 7,
"scale": 3.55
},
{
"zoom": 8,
"scale": 3.92
},
{
"zoom": 9,
"scale": 4.44
},
{
"zoom": 10,
"scale": 4.01
},
{
"zoom": 11,
"scale": 3.39
},
{
"zoom": 12,
"scale": 2.94
},
{
"zoom": 13,
"scale": 2.53
},
{
"zoom": 14,
"scale": 2.26
},
{
"zoom": 15,
"scale": 2.11
},
{
"zoom": 16,
"scale": 2.07
},
{
"zoom": 17,
"scale": 1.64
},
{
"zoom": 18,
"scale": 1.35
},
{
"zoom": 19,
"scale": 1.16
},
{
"zoom": 20,
"scale": 1.05
},
{
"zoom": 21,
"scale": 1
}
]
},
{
"tags": {
"any": "road_1"
},
"elements": "geometry.outline",
"stylers": [
{
"color": "#c8ccd0"
},
{
"zoom": 0,
"scale": 1
},
{
"zoom": 1,
"scale": 1
},
{
"zoom": 2,
"scale": 1
},
{
"zoom": 3,
"scale": 1
},
{
"zoom": 4,
"scale": 1
},
{
"zoom": 5,
"scale": 1
},
{
"zoom": 6,
"scale": 2.18
},
{
"zoom": 7,
"scale": 2.18
},
{
"zoom": 8,
"scale": 2.25
},
{
"zoom": 9,
"scale": 2.4
},
{
"zoom": 10,
"scale": 2.4
},
{
"zoom": 11,
"scale": 2.26
},
{
"zoom": 12,
"scale": 2.15
},
{
"zoom": 13,
"scale": 2
},
{
"zoom": 14,
"scale": 1.9
},
{
"zoom": 15,
"scale": 1.86
},
{
"zoom": 16,
"scale": 1.88
},
{
"zoom": 17,
"scale": 1.53
},
{
"zoom": 18,
"scale": 1.28
},
{
"zoom": 19,
"scale": 1.11
},
{
"zoom": 20,
"scale": 1.01
},
{
"zoom": 21,
"scale": 0.96
}
]
},
{
"tags": {
"any": "road_2",
"none": "is_tunnel"
},
"elements": "geometry.fill",
"stylers": [
{
"color": "#ffffff"
},
{
"zoom": 0,
"scale": 0
},
{
"zoom": 1,
"scale": 0
},
{
"zoom": 2,
"scale": 0
},
{
"zoom": 3,
"scale": 0
},
{
"zoom": 4,
"scale": 0
},
{
"zoom": 5,
"scale": 0
},
{
"zoom": 6,
"scale": 3.3
},
{
"zoom": 7,
"scale": 3.55
},
{
"zoom": 8,
"scale": 3.92
},
{
"zoom": 9,
"scale": 4.44
},
{
"zoom": 10,
"scale": 4.01
},
{
"zoom": 11,
"scale": 3.39
},
{
"zoom": 12,
"scale": 2.94
},
{
"zoom": 13,
"scale": 2.53
},
{
"zoom": 14,
"scale": 2.26
},
{
"zoom": 15,
"scale": 2.11
},
{
"zoom": 16,
"scale": 2.07
},
{
"zoom": 17,
"scale": 1.64
},
{
"zoom": 18,
"scale": 1.35
},
{
"zoom": 19,
"scale": 1.16
},
{
"zoom": 20,
"scale": 1.05
},
{
"zoom": 21,
"scale": 1
}
]
},
{
"tags": {
"any": "road_2"
},
"elements": "geometry.outline",
"stylers": [
{
"color": "#c8ccd0"
},
{
"zoom": 0,
"scale": 1
},
{
"zoom": 1,
"scale": 1
},
{
"zoom": 2,
"scale": 1
},
{
"zoom": 3,
"scale": 1
},
{
"zoom": 4,
"scale": 1
},
{
"zoom": 5,
"scale": 1
},
{
"zoom": 6,
"scale": 2.18
},
{
"zoom": 7,
"scale": 2.18
},
{
"zoom": 8,
"scale": 2.25
},
{
"zoom": 9,
"scale": 2.4
},
{
"zoom": 10,
"scale": 2.4
},
{
"zoom": 11,
"scale": 2.26
},
{
"zoom": 12,
"scale": 2.15
},
{
"zoom": 13,
"scale": 2
},
{
"zoom": 14,
"scale": 1.9
},
{
"zoom": 15,
"scale": 1.86
},
{
"zoom": 16,
"scale": 1.88
},
{
"zoom": 17,
"scale": 1.53
},
{
"zoom": 18,
"scale": 1.28
},
{
"zoom": 19,
"scale": 1.11
},
{
"zoom": 20,
"scale": 1.01
},
{
"zoom": 21,
"scale": 0.96
}
]
},
{
"tags": {
"any": "road_3",
"none": "is_tunnel"
},
"elements": "geometry.fill",
"stylers": [
{
"color": "#ffffff"
},
{
"zoom": 0,
"scale": 0
},
{
"zoom": 1,
"scale": 0
},
{
"zoom": 2,
"scale": 0
},
{
"zoom": 3,
"scale": 0
},
{
"zoom": 4,
"scale": 0
},
{
"zoom": 5,
"scale": 0
},
{
"zoom": 6,
"scale": 0
},
{
"zoom": 7,
"scale": 0
},
{
"zoom": 8,
"scale": 0
},
{
"zoom": 9,
"scale": 2.79
},
{
"zoom": 10,
"scale": 2.91
},
{
"zoom": 11,
"scale": 1.86
},
{
"zoom": 12,
"scale": 1.86
},
{
"zoom": 13,
"scale": 1.54
},
{
"zoom": 14,
"scale": 1.32
},
{
"zoom": 15,
"scale": 1.2
},
{
"zoom": 16,
"scale": 1.15
},
{
"zoom": 17,
"scale": 1.01
},
{
"zoom": 18,
"scale": 0.93
},
{
"zoom": 19,
"scale": 0.91
},
{
"zoom": 20,
"scale": 0.93
},
{
"zoom": 21,
"scale": 1
}
]
},
{
"tags": {
"any": "road_3"
},
"elements": "geometry.outline",
"stylers": [
{
"color": "#c8ccd0"
},
{
"zoom": 0,
"scale": 1.14
},
{
"zoom": 1,
"scale": 1.14
},
{
"zoom": 2,
"scale": 1.14
},
{
"zoom": 3,
"scale": 1.14
},
{
"zoom": 4,
"scale": 1.14
},
{
"zoom": 5,
"scale": 1.14
},
{
"zoom": 6,
"scale": 1.14
},
{
"zoom": 7,
"scale": 1.14
},
{
"zoom": 8,
"scale": 0.92
},
{
"zoom": 9,
"scale": 3.01
},
{
"zoom": 10,
"scale": 1.95
},
{
"zoom": 11,
"scale": 1.46
},
{
"zoom": 12,
"scale": 1.52
},
{
"zoom": 13,
"scale": 1.35
},
{
"zoom": 14,
"scale": 1.22
},
{
"zoom": 15,
"scale": 1.14
},
{
"zoom": 16,
"scale": 1.11
},
{
"zoom": 17,
"scale": 0.98
},
{
"zoom": 18,
"scale": 0.9
},
{
"zoom": 19,
"scale": 0.88
},
{
"zoom": 20,
"scale": 0.9
},
{
"zoom": 21,
"scale": 0.96
}
]
},
{
"tags": {
"any": "road_4",
"none": "is_tunnel"
},
"elements": "geometry.fill",
"stylers": [
{
"color": "#ffffff"
},
{
"zoom": 0,
"scale": 0
},
{
"zoom": 1,
"scale": 0
},
{
"zoom": 2,
"scale": 0
},
{
"zoom": 3,
"scale": 0
},
{
"zoom": 4,
"scale": 0
},
{
"zoom": 5,
"scale": 0
},
{
"zoom": 6,
"scale": 0
},
{
"zoom": 7,
"scale": 0
},
{
"zoom": 8,
"scale": 0
},
{
"zoom": 9,
"scale": 0
},
{
"zoom": 10,
"scale": 1.88
},
{
"zoom": 11,
"scale": 1.4
},
{
"zoom": 12,
"scale": 1.57
},
{
"zoom": 13,
"scale": 1.32
},
{
"zoom": 14,
"scale": 1.16
},
{
"zoom": 15,
"scale": 1.07
},
{
"zoom": 16,
"scale": 1.28
},
{
"zoom": 17,
"scale": 1.1
},
{
"zoom": 18,
"scale": 0.99
},
{
"zoom": 19,
"scale": 0.94
},
{
"zoom": 20,
"scale": 0.95
},
{
"zoom": 21,
"scale": 1
}
]
},
{
"tags": {
"any": "road_4"
},
"elements": "geometry.outline",
"stylers": [
{
"color": "#c8ccd0"
},
{
"zoom": 0,
"scale": 1
},
{
"zoom": 1,
"scale": 1
},
{
"zoom": 2,
"scale": 1
},
{
"zoom": 3,
"scale": 1
},
{
"zoom": 4,
"scale": 1
},
{
"zoom": 5,
"scale": 1
},
{
"zoom": 6,
"scale": 1
},
{
"zoom": 7,
"scale": 1
},
{
"zoom": 8,
"scale": 1
},
{
"zoom": 9,
"scale": 0.8
},
{
"zoom": 10,
"scale": 1.36
},
{
"zoom": 11,
"scale": 1.15
},
{
"zoom": 12,
"scale": 1.3
},
{
"zoom": 13,
"scale": 1.17
},
{
"zoom": 14,
"scale": 1.08
},
{
"zoom": 15,
"scale": 1.03
},
{
"zoom": 16,
"scale": 1.21
},
{
"zoom": 17,
"scale": 1.05
},
{
"zoom": 18,
"scale": 0.96
},
{
"zoom": 19,
"scale": 0.91
},
{
"zoom": 20,
"scale": 0.91
},
{
"zoom": 21,
"scale": 0.96
}
]
},
{
"tags": {
"any": "road_5",
"none": "is_tunnel"
},
"elements": "geometry.fill",
"stylers": [
{
"color": "#ffffff"
},
{
"zoom": 0,
"scale": 0
},
{
"zoom": 1,
"scale": 0
},
{
"zoom": 2,
"scale": 0
},
{
"zoom": 3,
"scale": 0
},
{
"zoom": 4,
"scale": 0
},
{
"zoom": 5,
"scale": 0
},
{
"zoom": 6,
"scale": 0
},
{
"zoom": 7,
"scale": 0
},
{
"zoom": 8,
"scale": 0
},
{
"zoom": 9,
"scale": 0
},
{
"zoom": 10,
"scale": 0
},
{
"zoom": 11,
"scale": 0
},
{
"zoom": 12,
"scale": 1.39
},
{
"zoom": 13,
"scale": 1.05
},
{
"zoom": 14,
"scale": 0.9
},
{
"zoom": 15,
"scale": 1.05
},
{
"zoom": 16,
"scale": 1.22
},
{
"zoom": 17,
"scale": 1.04
},
{
"zoom": 18,
"scale": 0.94
},
{
"zoom": 19,
"scale": 0.91
},
{
"zoom": 20,
"scale": 0.93
},
{
"zoom": 21,
"scale": 1
}
]
},
{
"tags": {
"any": "road_5"
},
"elements": "geometry.outline",
"stylers": [
{
"color": "#c8ccd0"
},
{
"zoom": 0,
"scale": 1
},
{
"zoom": 1,
"scale": 1
},
{
"zoom": 2,
"scale": 1
},
{
"zoom": 3,
"scale": 1
},
{
"zoom": 4,
"scale": 1
},
{
"zoom": 5,
"scale": 1
},
{
"zoom": 6,
"scale": 1
},
{
"zoom": 7,
"scale": 1
},
{
"zoom": 8,
"scale": 1
},
{
"zoom": 9,
"scale": 1
},
{
"zoom": 10,
"scale": 1
},
{
"zoom": 11,
"scale": 0.44
},
{
"zoom": 12,
"scale": 1.15
},
{
"zoom": 13,
"scale": 0.97
},
{
"zoom": 14,
"scale": 0.87
},
{
"zoom": 15,
"scale": 1.01
},
{
"zoom": 16,
"scale": 1.16
},
{
"zoom": 17,
"scale": 1
},
{
"zoom": 18,
"scale": 0.91
},
{
"zoom": 19,
"scale": 0.88
},
{
"zoom": 20,
"scale": 0.89
},
{
"zoom": 21,
"scale": 0.96
}
]
},
{
"tags": {
"any": "road_6",
"none": "is_tunnel"
},
"elements": "geometry.fill",
"stylers": [
{
"color": "#ffffff"
},
{
"zoom": 0,
"scale": 0
},
{
"zoom": 1,
"scale": 0
},
{
"zoom": 2,
"scale": 0
},
{
"zoom": 3,
"scale": 0
},
{
"zoom": 4,
"scale": 0
},
{
"zoom": 5,
"scale": 0
},
{
"zoom": 6,
"scale": 0
},
{
"zoom": 7,
"scale": 0
},
{
"zoom": 8,
"scale": 0
},
{
"zoom": 9,
"scale": 0
},
{
"zoom": 10,
"scale": 0
},
{
"zoom": 11,
"scale": 0
},
{
"zoom": 12,
"scale": 0
},
{
"zoom": 13,
"scale": 2.5
},
{
"zoom": 14,
"scale": 1.41
},
{
"zoom": 15,
"scale": 1.39
},
{
"zoom": 16,
"scale": 1.45
},
{
"zoom": 17,
"scale": 1.16
},
{
"zoom": 18,
"scale": 1
},
{
"zoom": 19,
"scale": 0.94
},
{
"zoom": 20,
"scale": 0.94
},
{
"zoom": 21,
"scale": 1
}
]
},
{
"tags": {
"any": "road_6"
},
"elements": "geometry.outline",
"stylers": [
{
"color": "#c8ccd0"
},
{
"zoom": 0,
"scale": 1
},
{
"zoom": 1,
"scale": 1
},
{
"zoom": 2,
"scale": 1
},
{
"zoom": 3,
"scale": 1
},
{
"zoom": 4,
"scale": 1
},
{
"zoom": 5,
"scale": 1
},
{
"zoom": 6,
"scale": 1
},
{
"zoom": 7,
"scale": 1
},
{
"zoom": 8,
"scale": 1
},
{
"zoom": 9,
"scale": 1
},
{
"zoom": 10,
"scale": 1
},
{
"zoom": 11,
"scale": 1
},
{
"zoom": 12,
"scale": 1
},
{
"zoom": 13,
"scale": 1.65
},
{
"zoom": 14,
"scale": 1.21
},
{
"zoom": 15,
"scale": 1.26
},
{
"zoom": 16,
"scale": 1.35
},
{
"zoom": 17,
"scale": 1.1
},
{
"zoom": 18,
"scale": 0.97
},
{
"zoom": 19,
"scale": 0.91
},
{
"zoom": 20,
"scale": 0.91
},
{
"zoom": 21,
"scale": 0.96
}
]
},
{
"tags": {
"any": "road_7",
"none": "is_tunnel"
},
"elements": "geometry.fill",
"stylers": [
{
"color": "#ffffff"
},
{
"zoom": 0,
"scale": 0
},
{
"zoom": 1,
"scale": 0
},
{
"zoom": 2,
"scale": 0
},
{
"zoom": 3,
"scale": 0
},
{
"zoom": 4,
"scale": 0
},
{
"zoom": 5,
"scale": 0
},
{
"zoom": 6,
"scale": 0
},
{
"zoom": 7,
"scale": 0
},
{
"zoom": 8,
"scale": 0
},
{
"zoom": 9,
"scale": 0
},
{
"zoom": 10,
"scale": 0
},
{
"zoom": 11,
"scale": 0
},
{
"zoom": 12,
"scale": 0
},
{
"zoom": 13,
"scale": 0
},
{
"zoom": 14,
"scale": 1
},
{
"zoom": 15,
"scale": 0.87
},
{
"zoom": 16,
"scale": 0.97
},
{
"zoom": 17,
"scale": 0.89
},
{
"zoom": 18,
"scale": 0.86
},
{
"zoom": 19,
"scale": 0.88
},
{
"zoom": 20,
"scale": 0.92
},
{
"zoom": 21,
"scale": 1
}
]
},
{
"tags": {
"any": "road_7"
},
"elements": "geometry.outline",
"stylers": [
{
"color": "#c8ccd0"
},
{
"zoom": 0,
"scale": 1
},
{
"zoom": 1,
"scale": 1
},
{
"zoom": 2,
"scale": 1
},
{
"zoom": 3,
"scale": 1
},
{
"zoom": 4,
"scale": 1
},
{
"zoom": 5,
"scale": 1
},
{
"zoom": 6,
"scale": 1
},
{
"zoom": 7,
"scale": 1
},
{
"zoom": 8,
"scale": 1
},
{
"zoom": 9,
"scale": 1
},
{
"zoom": 10,
"scale": 1
},
{
"zoom": 11,
"scale": 1
},
{
"zoom": 12,
"scale": 1
},
{
"zoom": 13,
"scale": 1
},
{
"zoom": 14,
"scale": 0.93
},
{
"zoom": 15,
"scale": 0.85
},
{
"zoom": 16,
"scale": 0.94
},
{
"zoom": 17,
"scale": 0.86
},
{
"zoom": 18,
"scale": 0.83
},
{
"zoom": 19,
"scale": 0.84
},
{
"zoom": 20,
"scale": 0.88
},
{
"zoom": 21,
"scale": 0.95
}
]
},
{
"tags": {
"any": "road_minor",
"none": "is_tunnel"
},
"elements": "geometry.fill",
"stylers": [
{
"color": "#ffffff"
},
{
"zoom": 0,
"scale": 0
},
{
"zoom": 1,
"scale": 0
},
{
"zoom": 2,
"scale": 0
},
{
"zoom": 3,
"scale": 0
},
{
"zoom": 4,
"scale": 0
},
{
"zoom": 5,
"scale": 0
},
{
"zoom": 6,
"scale": 0
},
{
"zoom": 7,
"scale": 0
},
{
"zoom": 8,
"scale": 0
},
{
"zoom": 9,
"scale": 0
},
{
"zoom": 10,
"scale": 0
},
{
"zoom": 11,
"scale": 0
},
{
"zoom": 12,
"scale": 0
},
{
"zoom": 13,
"scale": 0
},
{
"zoom": 14,
"scale": 0
},
{
"zoom": 15,
"scale": 0
},
{
"zoom": 16,
"scale": 1
},
{
"zoom": 17,
"scale": 1
},
{
"zoom": 18,
"scale": 1
},
{
"zoom": 19,
"scale": 1
},
{
"zoom": 20,
"scale": 1
},
{
"zoom": 21,
"scale": 1
}
]
},
{
"tags": {
"any": "road_minor"
},
"elements": "geometry.outline",
"stylers": [
{
"color": "#c8ccd0"
},
{
"zoom": 0,
"scale": 0.29
},
{
"zoom": 1,
"scale": 0.29
},
{
"zoom": 2,
"scale": 0.29
},
{
"zoom": 3,
"scale": 0.29
},
{
"zoom": 4,
"scale": 0.29
},
{
"zoom": 5,
"scale": 0.29
},
{
"zoom": 6,
"scale": 0.29
},
{
"zoom": 7,
"scale": 0.29
},
{
"zoom": 8,
"scale": 0.29
},
{
"zoom": 9,
"scale": 0.29
},
{
"zoom": 10,
"scale": 0.29
},
{
"zoom": 11,
"scale": 0.29
},
{
"zoom": 12,
"scale": 0.29
},
{
"zoom": 13,
"scale": 0.29
},
{
"zoom": 14,
"scale": 0.29
},
{
"zoom": 15,
"scale": 0.29
},
{
"zoom": 16,
"scale": 1
},
{
"zoom": 17,
"scale": 0.9
},
{
"zoom": 18,
"scale": 0.91
},
{
"zoom": 19,
"scale": 0.92
},
{
"zoom": 20,
"scale": 0.93
},
{
"zoom": 21,
"scale": 0.95
}
]
},
{
"tags": {
"any": "road_unclassified",
"none": "is_tunnel"
},
"elements": "geometry.fill",
"stylers": [
{
"color": "#ffffff"
},
{
"zoom": 0,
"scale": 0
},
{
"zoom": 1,
"scale": 0
},
{
"zoom": 2,
"scale": 0
},
{
"zoom": 3,
"scale": 0
},
{
"zoom": 4,
"scale": 0
},
{
"zoom": 5,
"scale": 0
},
{
"zoom": 6,
"scale": 0
},
{
"zoom": 7,
"scale": 0
},
{
"zoom": 8,
"scale": 0
},
{
"zoom": 9,
"scale": 0
},
{
"zoom": 10,
"scale": 0
},
{
"zoom": 11,
"scale": 0
},
{
"zoom": 12,
"scale": 0
},
{
"zoom": 13,
"scale": 0
},
{
"zoom": 14,
"scale": 0
},
{
"zoom": 15,
"scale": 0
},
{
"zoom": 16,
"scale": 1
},
{
"zoom": 17,
"scale": 1
},
{
"zoom": 18,
"scale": 1
},
{
"zoom": 19,
"scale": 1
},
{
"zoom": 20,
"scale": 1
},
{
"zoom": 21,
"scale": 1
}
]
},
{
"tags": {
"any": "road_unclassified"
},
"elements": "geometry.outline",
"stylers": [
{
"color": "#c8ccd0"
},
{
"zoom": 0,
"scale": 0.29
},
{
"zoom": 1,
"scale": 0.29
},
{
"zoom": 2,
"scale": 0.29
},
{
"zoom": 3,
"scale": 0.29
},
{
"zoom": 4,
"scale": 0.29
},
{
"zoom": 5,
"scale": 0.29
},
{
"zoom": 6,
"scale": 0.29
},
{
"zoom": 7,
"scale": 0.29
},
{
"zoom": 8,
"scale": 0.29
},
{
"zoom": 9,
"scale": 0.29
},
{
"zoom": 10,
"scale": 0.29
},
{
"zoom": 11,
"scale": 0.29
},
{
"zoom": 12,
"scale": 0.29
},
{
"zoom": 13,
"scale": 0.29
},
{
"zoom": 14,
"scale": 0.29
},
{
"zoom": 15,
"scale": 0.29
},
{
"zoom": 16,
"scale": 1
},
{
"zoom": 17,
"scale": 0.9
},
{
"zoom": 18,
"scale": 0.91
},
{
"zoom": 19,
"scale": 0.92
},
{
"zoom": 20,
"scale": 0.93
},
{
"zoom": 21,
"scale": 0.95
}
]
},
{
"tags": {
"all": "is_tunnel",
"none": "path"
},
"elements": "geometry.fill",
"stylers": [
{
"zoom": 0,
"color": "#dcdee0"
},
{
"zoom": 1,
"color": "#dcdee0"
},
{
"zoom": 2,
"color": "#dcdee0"
},
{
"zoom": 3,
"color": "#dcdee0"
},
{
"zoom": 4,
"color": "#dcdee0"
},
{
"zoom": 5,
"color": "#dcdee0"
},
{
"zoom": 6,
"color": "#dcdee0"
},
{
"zoom": 7,
"color": "#dcdee0"
},
{
"zoom": 8,
"color": "#dcdee0"
},
{
"zoom": 9,
"color": "#dcdee0"
},
{
"zoom": 10,
"color": "#dcdee0"
},
{
"zoom": 11,
"color": "#dcdee0"
},
{
"zoom": 12,
"color": "#dcdee0"
},
{
"zoom": 13,
"color": "#dcdee0"
},
{
"zoom": 14,
"color": "#e1e3e5"
},
{
"zoom": 15,
"color": "#e6e8ea"
},
{
"zoom": 16,
"color": "#e7e9eb"
},
{
"zoom": 17,
"color": "#e8eaeb"
},
{
"zoom": 18,
"color": "#e9eaec"
},
{
"zoom": 19,
"color": "#eaebed"
},
{
"zoom": 20,
"color": "#ebeced"
},
{
"zoom": 21,
"color": "#ecedee"
}
]
},
{
"tags": {
"all": "path",
"none": "is_tunnel"
},
"elements": "geometry.fill",
"stylers": [
{
"color": "#c8ccd0"
}
]
},
{
"tags": {
"all": "path",
"none": "is_tunnel"
},
"elements": "geometry.outline",
"stylers": [
{
"opacity": 0.7
},
{
"zoom": 0,
"color": "#e1e3e5"
},
{
"zoom": 1,
"color": "#e1e3e5"
},
{
"zoom": 2,
"color": "#e1e3e5"
},
{
"zoom": 3,
"color": "#e1e3e5"
},
{
"zoom": 4,
"color": "#e1e3e5"
},
{
"zoom": 5,
"color": "#e1e3e5"
},
{
"zoom": 6,
"color": "#e1e3e5"
},
{
"zoom": 7,
"color": "#e1e3e5"
},
{
"zoom": 8,
"color": "#e1e3e5"
},
{
"zoom": 9,
"color": "#e1e3e5"
},
{
"zoom": 10,
"color": "#e1e3e5"
},
{
"zoom": 11,
"color": "#e1e3e5"
},
{
"zoom": 12,
"color": "#e1e3e5"
},
{
"zoom": 13,
"color": "#e1e3e5"
},
{
"zoom": 14,
"color": "#e6e8e9"
},
{
"zoom": 15,
"color": "#ecedee"
},
{
"zoom": 16,
"color": "#edeeef"
},
{
"zoom": 17,
"color": "#eeeff0"
},
{
"zoom": 18,
"color": "#eeeff0"
},
{
"zoom": 19,
"color": "#eff0f1"
},
{
"zoom": 20,
"color": "#f0f1f2"
},
{
"zoom": 21,
"color": "#f1f2f3"
}
]
},
{
"tags": "road_construction",
"elements": "geometry.fill",
"stylers": [
{
"color": "#ffffff"
}
]
},
{
"tags": "road_construction",
"elements": "geometry.outline",
"stylers": [
{
"zoom": 0,
"color": "#e4e6e8"
},
{
"zoom": 1,
"color": "#e4e6e8"
},
{
"zoom": 2,
"color": "#e4e6e8"
},
{
"zoom": 3,
"color": "#e4e6e8"
},
{
"zoom": 4,
"color": "#e4e6e8"
},
{
"zoom": 5,
"color": "#e4e6e8"
},
{
"zoom": 6,
"color": "#e4e6e8"
},
{
"zoom": 7,
"color": "#e4e6e8"
},
{
"zoom": 8,
"color": "#e4e6e8"
},
{
"zoom": 9,
"color": "#e4e6e8"
},
{
"zoom": 10,
"color": "#e4e6e8"
},
{
"zoom": 11,
"color": "#e4e6e8"
},
{
"zoom": 12,
"color": "#e4e6e8"
},
{
"zoom": 13,
"color": "#e4e6e8"
},
{
"zoom": 14,
"color": "#c8ccd0"
},
{
"zoom": 15,
"color": "#e4e6e8"
},
{
"zoom": 16,
"color": "#e8eaec"
},
{
"zoom": 17,
"color": "#edeef0"
},
{
"zoom": 18,
"color": "#f1f2f3"
},
{
"zoom": 19,
"color": "#f6f7f7"
},
{
"zoom": 20,
"color": "#fafbfb"
},
{
"zoom": 21,
"color": "#ffffff"
}
]
},
{
"tags": {
"any": "ferry"
},
"stylers": [
{
"color": "#919ba4"
}
]
},
{
"tags": "transit_location",
"elements": "label.icon",
"stylers": [
{
"saturation": -1
},
{
"zoom": 0,
"opacity": 0
},
{
"zoom": 1,
"opacity": 0
},
{
"zoom": 2,
"opacity": 0
},
{
"zoom": 3,
"opacity": 0
},
{
"zoom": 4,
"opacity": 0
},
{
"zoom": 5,
"opacity": 0
},
{
"zoom": 6,
"opacity": 0
},
{
"zoom": 7,
"opacity": 0
},
{
"zoom": 8,
"opacity": 0
},
{
"zoom": 9,
"opacity": 0
},
{
"zoom": 10,
"opacity": 0
},
{
"zoom": 11,
"opacity": 0
},
{
"zoom": 12,
"opacity": 0
},
{
"zoom": 13,
"opacity": 1
},
{
"zoom": 14,
"opacity": 1
},
{
"zoom": 15,
"opacity": 1
},
{
"zoom": 16,
"opacity": 1
},
{
"zoom": 17,
"opacity": 1
},
{
"zoom": 18,
"opacity": 1
},
{
"zoom": 19,
"opacity": 1
},
{
"zoom": 20,
"opacity": 1
},
{
"zoom": 21,
"opacity": 1
}
]
},
{
"tags": "transit_location",
"elements": "label.text",
"stylers": [
{
"zoom": 0,
"opacity": 0
},
{
"zoom": 1,
"opacity": 0
},
{
"zoom": 2,
"opacity": 0
},
{
"zoom": 3,
"opacity": 0
},
{
"zoom": 4,
"opacity": 0
},
{
"zoom": 5,
"opacity": 0
},
{
"zoom": 6,
"opacity": 0
},
{
"zoom": 7,
"opacity": 0
},
{
"zoom": 8,
"opacity": 0
},
{
"zoom": 9,
"opacity": 0
},
{
"zoom": 10,
"opacity": 0
},
{
"zoom": 11,
"opacity": 0
},
{
"zoom": 12,
"opacity": 0
},
{
"zoom": 13,
"opacity": 1
},
{
"zoom": 14,
"opacity": 1
},
{
"zoom": 15,
"opacity": 1
},
{
"zoom": 16,
"opacity": 1
},
{
"zoom": 17,
"opacity": 1
},
{
"zoom": 18,
"opacity": 1
},
{
"zoom": 19,
"opacity": 1
},
{
"zoom": 20,
"opacity": 1
},
{
"zoom": 21,
"opacity": 1
}
]
},
{
"tags": "transit_location",
"elements": "label.text.fill",
"stylers": [
{
"color": "#6c8993"
}
]
},
{
"tags": "transit_location",
"elements": "label.text.outline",
"stylers": [
{
"color": "#ffffff"
}
]
},
{
"tags": "transit_schema",
"elements": "geometry.fill",
"stylers": [
{
"color": "#6c8993"
},
{
"scale": 0.7
},
{
"zoom": 0,
"opacity": 0.6
},
{
"zoom": 1,
"opacity": 0.6
},
{
"zoom": 2,
"opacity": 0.6
},
{
"zoom": 3,
"opacity": 0.6
},
{
"zoom": 4,
"opacity": 0.6
},
{
"zoom": 5,
"opacity": 0.6
},
{
"zoom": 6,
"opacity": 0.6
},
{
"zoom": 7,
"opacity": 0.6
},
{
"zoom": 8,
"opacity": 0.6
},
{
"zoom": 9,
"opacity": 0.6
},
{
"zoom": 10,
"opacity": 0.6
},
{
"zoom": 11,
"opacity": 0.6
},
{
"zoom": 12,
"opacity": 0.6
},
{
"zoom": 13,
"opacity": 0.6
},
{
"zoom": 14,
"opacity": 0.6
},
{
"zoom": 15,
"opacity": 0.5
},
{
"zoom": 16,
"opacity": 0.4
},
{
"zoom": 17,
"opacity": 0.4
},
{
"zoom": 18,
"opacity": 0.4
},
{
"zoom": 19,
"opacity": 0.4
},
{
"zoom": 20,
"opacity": 0.4
},
{
"zoom": 21,
"opacity": 0.4
}
]
},
{
"tags": "transit_schema",
"elements": "geometry.outline",
"stylers": [
{
"opacity": 0
}
]
},
{
"tags": "transit_line",
"elements": "geometry.fill.pattern",
"stylers": [
{
"color": "#949c9e"
},
{
"zoom": 0,
"opacity": 0
},
{
"zoom": 1,
"opacity": 0
},
{
"zoom": 2,
"opacity": 0
},
{
"zoom": 3,
"opacity": 0
},
{
"zoom": 4,
"opacity": 0
},
{
"zoom": 5,
"opacity": 0
},
{
"zoom": 6,
"opacity": 0
},
{
"zoom": 7,
"opacity": 0
},
{
"zoom": 8,
"opacity": 0
},
{
"zoom": 9,
"opacity": 0
},
{
"zoom": 10,
"opacity": 0
},
{
"zoom": 11,
"opacity": 0
},
{
"zoom": 12,
"opacity": 0
},
{
"zoom": 13,
"opacity": 1
},
{
"zoom": 14,
"opacity": 1
},
{
"zoom": 15,
"opacity": 1
},
{
"zoom": 16,
"opacity": 1
},
{
"zoom": 17,
"opacity": 1
},
{
"zoom": 18,
"opacity": 1
},
{
"zoom": 19,
"opacity": 1
},
{
"zoom": 20,
"opacity": 1
},
{
"zoom": 21,
"opacity": 1
}
]
},
{
"tags": "transit_line",
"elements": "geometry.fill",
"stylers": [
{
"color": "#949c9e"
},
{
"scale": 0.4
},
{
"zoom": 0,
"opacity": 0
},
{
"zoom": 1,
"opacity": 0
},
{
"zoom": 2,
"opacity": 0
},
{
"zoom": 3,
"opacity": 0
},
{
"zoom": 4,
"opacity": 0
},
{
"zoom": 5,
"opacity": 0
},
{
"zoom": 6,
"opacity": 0
},
{
"zoom": 7,
"opacity": 0
},
{
"zoom": 8,
"opacity": 0
},
{
"zoom": 9,
"opacity": 0
},
{
"zoom": 10,
"opacity": 0
},
{
"zoom": 11,
"opacity": 0
},
{
"zoom": 12,
"opacity": 0
},
{
"zoom": 13,
"opacity": 1
},
{
"zoom": 14,
"opacity": 1
},
{
"zoom": 15,
"opacity": 1
},
{
"zoom": 16,
"opacity": 1
},
{
"zoom": 17,
"opacity": 1
},
{
"zoom": 18,
"opacity": 1
},
{
"zoom": 19,
"opacity": 1
},
{
"zoom": 20,
"opacity": 1
},
{
"zoom": 21,
"opacity": 1
}
]
},
{
"tags": "water",
"elements": "geometry",
"stylers": [
{
"zoom": 0,
"color": "#adb4bb"
},
{
"zoom": 1,
"color": "#adb4bb"
},
{
"zoom": 2,
"color": "#adb4bb"
},
{
"zoom": 3,
"color": "#adb4bb"
},
{
"zoom": 4,
"color": "#adb4bb"
},
{
"zoom": 5,
"color": "#adb4bb"
},
{
"zoom": 6,
"color": "#adb4bb"
},
{
"zoom": 7,
"color": "#adb4bb"
},
{
"zoom": 8,
"color": "#afb6bd"
},
{
"zoom": 9,
"color": "#b1b7be"
},
{
"zoom": 10,
"color": "#b3b9c0"
},
{
"zoom": 11,
"color": "#b4bac1"
},
{
"zoom": 12,
"color": "#b4bbc1"
},
{
"zoom": 13,
"color": "#b5bcc2"
},
{
"zoom": 14,
"color": "#b6bdc3"
},
{
"zoom": 15,
"color": "#b8bec4"
},
{
"zoom": 16,
"color": "#b9c0c5"
},
{
"zoom": 17,
"color": "#bbc1c6"
},
{
"zoom": 18,
"color": "#bcc2c8"
},
{
"zoom": 19,
"color": "#bec3c9"
},
{
"zoom": 20,
"color": "#bfc5ca"
},
{
"zoom": 21,
"color": "#c1c6cb"
}
]
},
{
"tags": "water",
"elements": "geometry",
"types": "polyline",
"stylers": [
{
"zoom": 0,
"opacity": 0.4
},
{
"zoom": 1,
"opacity": 0.4
},
{
"zoom": 2,
"opacity": 0.4
},
{
"zoom": 3,
"opacity": 0.4
},
{
"zoom": 4,
"opacity": 0.6
},
{
"zoom": 5,
"opacity": 0.8
},
{
"zoom": 6,
"opacity": 1
},
{
"zoom": 7,
"opacity": 1
},
{
"zoom": 8,
"opacity": 1
},
{
"zoom": 9,
"opacity": 1
},
{
"zoom": 10,
"opacity": 1
},
{
"zoom": 11,
"opacity": 1
},
{
"zoom": 12,
"opacity": 1
},
{
"zoom": 13,
"opacity": 1
},
{
"zoom": 14,
"opacity": 1
},
{
"zoom": 15,
"opacity": 1
},
{
"zoom": 16,
"opacity": 1
},
{
"zoom": 17,
"opacity": 1
},
{
"zoom": 18,
"opacity": 1
},
{
"zoom": 19,
"opacity": 1
},
{
"zoom": 20,
"opacity": 1
},
{
"zoom": 21,
"opacity": 1
}
]
},
{
"tags": "bathymetry",
"elements": "geometry",
"stylers": [
{
"hue": "#adb4bb"
}
]
},
{
"tags": {
"any": [
"industrial",
"construction_site"
]
},
"elements": "geometry",
"stylers": [
{
"zoom": 0,
"color": "#dcdee0"
},
{
"zoom": 1,
"color": "#dcdee0"
},
{
"zoom": 2,
"color": "#dcdee0"
},
{
"zoom": 3,
"color": "#dcdee0"
},
{
"zoom": 4,
"color": "#dcdee0"
},
{
"zoom": 5,
"color": "#dcdee0"
},
{
"zoom": 6,
"color": "#dcdee0"
},
{
"zoom": 7,
"color": "#dcdee0"
},
{
"zoom": 8,
"color": "#dcdee0"
},
{
"zoom": 9,
"color": "#dcdee0"
},
{
"zoom": 10,
"color": "#dcdee0"
},
{
"zoom": 11,
"color": "#dcdee0"
},
{
"zoom": 12,
"color": "#dcdee0"
},
{
"zoom": 13,
"color": "#dcdee0"
},
{
"zoom": 14,
"color": "#e1e3e5"
},
{
"zoom": 15,
"color": "#e7e8ea"
},
{
"zoom": 16,
"color": "#e8e9eb"
},
{
"zoom": 17,
"color": "#e9eaeb"
},
{
"zoom": 18,
"color": "#e9eaec"
},
{
"zoom": 19,
"color": "#eaebed"
},
{
"zoom": 20,
"color": "#ebeced"
},
{
"zoom": 21,
"color": "#ecedee"
}
]
},
{
"tags": {
"any": "transit",
"none": [
"transit_location",
"transit_line",
"transit_schema",
"is_unclassified_transit"
]
},
"elements": "geometry",
"stylers": [
{
"zoom": 0,
"color": "#dcdee0"
},
{
"zoom": 1,
"color": "#dcdee0"
},
{
"zoom": 2,
"color": "#dcdee0"
},
{
"zoom": 3,
"color": "#dcdee0"
},
{
"zoom": 4,
"color": "#dcdee0"
},
{
"zoom": 5,
"color": "#dcdee0"
},
{
"zoom": 6,
"color": "#dcdee0"
},
{
"zoom": 7,
"color": "#dcdee0"
},
{
"zoom": 8,
"color": "#dcdee0"
},
{
"zoom": 9,
"color": "#dcdee0"
},
{
"zoom": 10,
"color": "#dcdee0"
},
{
"zoom": 11,
"color": "#dcdee0"
},
{
"zoom": 12,
"color": "#dcdee0"
},
{
"zoom": 13,
"color": "#dcdee0"
},
{
"zoom": 14,
"color": "#e1e3e5"
},
{
"zoom": 15,
"color": "#e7e8ea"
},
{
"zoom": 16,
"color": "#e8e9eb"
},
{
"zoom": 17,
"color": "#e9eaeb"
},
{
"zoom": 18,
"color": "#e9eaec"
},
{
"zoom": 19,
"color": "#eaebed"
},
{
"zoom": 20,
"color": "#ebeced"
},
{
"zoom": 21,
"color": "#ecedee"
}
]
},
{
"tags": "fence",
"elements": "geometry.fill",
"stylers": [
{
"color": "#d1d4d6"
},
{
"zoom": 0,
"opacity": 0.75
},
{
"zoom": 1,
"opacity": 0.75
},
{
"zoom": 2,
"opacity": 0.75
},
{
"zoom": 3,
"opacity": 0.75
},
{
"zoom": 4,
"opacity": 0.75
},
{
"zoom": 5,
"opacity": 0.75
},
{
"zoom": 6,
"opacity": 0.75
},
{
"zoom": 7,
"opacity": 0.75
},
{
"zoom": 8,
"opacity": 0.75
},
{
"zoom": 9,
"opacity": 0.75
},
{
"zoom": 10,
"opacity": 0.75
},
{
"zoom": 11,
"opacity": 0.75
},
{
"zoom": 12,
"opacity": 0.75
},
{
"zoom": 13,
"opacity": 0.75
},
{
"zoom": 14,
"opacity": 0.75
},
{
"zoom": 15,
"opacity": 0.75
},
{
"zoom": 16,
"opacity": 0.75
},
{
"zoom": 17,
"opacity": 0.45
},
{
"zoom": 18,
"opacity": 0.45
},
{
"zoom": 19,
"opacity": 0.45
},
{
"zoom": 20,
"opacity": 0.45
},
{
"zoom": 21,
"opacity": 0.45
}
]
},
{
"tags": "medical",
"elements": "geometry",
"stylers": [
{
"zoom": 0,
"color": "#dcdee0"
},
{
"zoom": 1,
"color": "#dcdee0"
},
{
"zoom": 2,
"color": "#dcdee0"
},
{
"zoom": 3,
"color": "#dcdee0"
},
{
"zoom": 4,
"color": "#dcdee0"
},
{
"zoom": 5,
"color": "#dcdee0"
},
{
"zoom": 6,
"color": "#dcdee0"
},
{
"zoom": 7,
"color": "#dcdee0"
},
{
"zoom": 8,
"color": "#dcdee0"
},
{
"zoom": 9,
"color": "#dcdee0"
},
{
"zoom": 10,
"color": "#dcdee0"
},
{
"zoom": 11,
"color": "#dcdee0"
},
{
"zoom": 12,
"color": "#dcdee0"
},
{
"zoom": 13,
"color": "#dcdee0"
},
{
"zoom": 14,
"color": "#e1e3e5"
},
{
"zoom": 15,
"color": "#e7e8ea"
},
{
"zoom": 16,
"color": "#e8e9eb"
},
{
"zoom": 17,
"color": "#e9eaeb"
},
{
"zoom": 18,
"color": "#e9eaec"
},
{
"zoom": 19,
"color": "#eaebed"
},
{
"zoom": 20,
"color": "#ebeced"
},
{
"zoom": 21,
"color": "#ecedee"
}
]
},
{
"tags": "beach",
"elements": "geometry",
"stylers": [
{
"zoom": 0,
"color": "#dcdee0",
"opacity": 0.3
},
{
"zoom": 1,
"color": "#dcdee0",
"opacity": 0.3
},
{
"zoom": 2,
"color": "#dcdee0",
"opacity": 0.3
},
{
"zoom": 3,
"color": "#dcdee0",
"opacity": 0.3
},
{
"zoom": 4,
"color": "#dcdee0",
"opacity": 0.3
},
{
"zoom": 5,
"color": "#dcdee0",
"opacity": 0.3
},
{
"zoom": 6,
"color": "#dcdee0",
"opacity": 0.3
},
{
"zoom": 7,
"color": "#dcdee0",
"opacity": 0.3
},
{
"zoom": 8,
"color": "#dcdee0",
"opacity": 0.3
},
{
"zoom": 9,
"color": "#dcdee0",
"opacity": 0.3
},
{
"zoom": 10,
"color": "#dcdee0",
"opacity": 0.3
},
{
"zoom": 11,
"color": "#dcdee0",
"opacity": 0.3
},
{
"zoom": 12,
"color": "#dcdee0",
"opacity": 0.3
},
{
"zoom": 13,
"color": "#dcdee0",
"opacity": 0.65
},
{
"zoom": 14,
"color": "#e1e3e5",
"opacity": 1
},
{
"zoom": 15,
"color": "#e7e8ea",
"opacity": 1
},
{
"zoom": 16,
"color": "#e8e9eb",
"opacity": 1
},
{
"zoom": 17,
"color": "#e9eaeb",
"opacity": 1
},
{
"zoom": 18,
"color": "#e9eaec",
"opacity": 1
},
{
"zoom": 19,
"color": "#eaebed",
"opacity": 1
},
{
"zoom": 20,
"color": "#ebeced",
"opacity": 1
},
{
"zoom": 21,
"color": "#ecedee",
"opacity": 1
}
]
},
{
"tags": {
"all": [
"is_tunnel",
"path"
]
},
"elements": "geometry.fill",
"stylers": [
{
"color": "#c3c7cb"
},
{
"opacity": 0.3
}
]
},
{
"tags": {
"all": [
"is_tunnel",
"path"
]
},
"elements": "geometry.outline",
"stylers": [
{
"opacity": 0
}
]
},
{
"tags": "road_limited",
"elements": "geometry.fill",
"stylers": [
{
"color": "#c8ccd0"
},
{
"zoom": 0,
"scale": 0
},
{
"zoom": 1,
"scale": 0
},
{
"zoom": 2,
"scale": 0
},
{
"zoom": 3,
"scale": 0
},
{
"zoom": 4,
"scale": 0
},
{
"zoom": 5,
"scale": 0
},
{
"zoom": 6,
"scale": 0
},
{
"zoom": 7,
"scale": 0
},
{
"zoom": 8,
"scale": 0
},
{
"zoom": 9,
"scale": 0
},
{
"zoom": 10,
"scale": 0
},
{
"zoom": 11,
"scale": 0
},
{
"zoom": 12,
"scale": 0
},
{
"zoom": 13,
"scale": 0.1
},
{
"zoom": 14,
"scale": 0.2
},
{
"zoom": 15,
"scale": 0.3
},
{
"zoom": 16,
"scale": 0.5
},
{
"zoom": 17,
"scale": 0.6
},
{
"zoom": 18,
"scale": 0.7
},
{
"zoom": 19,
"scale": 0.88
},
{
"zoom": 20,
"scale": 0.92
},
{
"zoom": 21,
"scale": 1
}
]
},
{
"tags": "road_limited",
"elements": "geometry.outline",
"stylers": [
{
"color": "#c8ccd0"
},
{
"zoom": 0,
"scale": 1
},
{
"zoom": 1,
"scale": 1
},
{
"zoom": 2,
"scale": 1
},
{
"zoom": 3,
"scale": 1
},
{
"zoom": 4,
"scale": 1
},
{
"zoom": 5,
"scale": 1
},
{
"zoom": 6,
"scale": 1
},
{
"zoom": 7,
"scale": 1
},
{
"zoom": 8,
"scale": 1
},
{
"zoom": 9,
"scale": 1
},
{
"zoom": 10,
"scale": 1
},
{
"zoom": 11,
"scale": 1
},
{
"zoom": 12,
"scale": 1
},
{
"zoom": 13,
"scale": 0.1
},
{
"zoom": 14,
"scale": 0.2
},
{
"zoom": 15,
"scale": 0.3
},
{
"zoom": 16,
"scale": 0.5
},
{
"zoom": 17,
"scale": 0.6
},
{
"zoom": 18,
"scale": 0.7
},
{
"zoom": 19,
"scale": 0.84
},
{
"zoom": 20,
"scale": 0.88
},
{
"zoom": 21,
"scale": 0.95
}
]
},
{
"tags": {
"any": "landcover",
"none": "vegetation"
},
"stylers": {
"visibility": "off"
}
}
]
''';

  @override
  void initState() {
    super.initState();
    _loadProfilesThenProperties();
  }

  Future<void> _loadProfilesThenProperties() async {
    if (!widget.isLandlordMode) {
      final profiles = await _scoringService.getMyProfiles();
      if (mounted) {
        setState(() {
          _myProfiles = profiles;
          _activeProfile = null; // не выбираем автоматически — ждём явного выбора
        });
      }
    }
    _loadProperties();
  }

  // Публичный метод — вызывается родительским экраном при возврате
  // на вкладку карты, чтобы подхватить только что созданные проекты поиска
  // без перезапуска приложения.
  Future<void> reloadProfiles() async {
    if (widget.isLandlordMode) return;
    final profiles = await _scoringService.getMyProfiles();
    if (!mounted) return;
    setState(() {
      _myProfiles = profiles;
      // Если активный профиль удалили из списка — сбрасываем выбор.
      if (_activeProfile != null &&
          !profiles.any((p) => p.id == _activeProfile!.id)) {
        _activeProfile = null;
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ── ПОИСК АДРЕСА (для верхней панели карты арендатора) ─────────────────
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchSuggestions = [];
        _isSearchingAddress = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!_mapControllerReady) return;
      setState(() => _isSearchingAddress = true);
      try {
        final region = await mapController.getVisibleRegion();
        final suggestTuple = await YandexSuggest.getSuggestions(
          text: trimmed,
          boundingBox: BoundingBox(
            southWest: region.bottomLeft,
            northEast: region.topRight,
          ),
          suggestOptions: const SuggestOptions(
            suggestType: SuggestType.geo,
            suggestWords: true,
          ),
        );
        final result = await suggestTuple.$2;
        if (!mounted) return;
        setState(() {
          _searchSuggestions = result.items ?? [];
          _isSearchingAddress = false;
        });
      } catch (e) {
        debugPrint('Ошибка Suggest на карте: $e');
        if (mounted) {
          setState(() {
            _searchSuggestions = [];
            _isSearchingAddress = false;
          });
        }
      }
    });
  }

  Future<void> _onSuggestionTapped(SuggestItem item) async {
    FocusScope.of(context).unfocus();
    final fullAddress = '${item.title} ${item.subtitle ?? ''}'.trim();
    setState(() {
      _searchController.text = item.title;
      _searchSuggestions = [];
    });
    await _performAddressSearch(fullAddress);
  }

  Future<void> _performAddressSearch(String query) async {
    if (query.trim().isEmpty || !_mapControllerReady) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searchSuggestions = [];
      _isSearchingAddress = true;
    });

    try {
      final searchTuple = await YandexSearch.searchByText(
        searchText: query,
        geometry: Geometry.fromBoundingBox(
          const BoundingBox(
            southWest: Point(latitude: -89, longitude: -180),
            northEast: Point(latitude: 89, longitude: 180),
          ),
        ),
        searchOptions: const SearchOptions(searchType: SearchType.geo),
      );
      final result = await searchTuple.$2;

      Point? target;
      if (result.items != null && result.items!.isNotEmpty) {
        final top = result.items!.first;
        target = top.toponymMetadata?.balloonPoint ??
            (top.geometry.isNotEmpty ? top.geometry.first.point : null);
      }

      if (target != null) {
        await mapController.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: target, zoom: 16),
          ),
          animation: const MapAnimation(
            type: MapAnimationType.smooth,
            duration: 1.2,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Адрес не найден. Уточните запрос.')),
        );
      }
    } catch (e) {
      debugPrint('Ошибка поиска адреса: $e');
    } finally {
      if (mounted) setState(() => _isSearchingAddress = false);
    }
  }

  Future<void> _loadProperties() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      List<Property> properties;
      final Map<int, ScoredProperty> newCache = {};

      if (_activeProfile != null && !widget.isLandlordMode) {
        final scored = await _scoringService.getScoredProperties(_activeProfile!.id);
        for (final sp in scored) {
          newCache[sp.property.id] = sp;
        }
        properties = scored.map((sp) => sp.property).toList();
      } else {
        properties = await _propertyService.getAllProperties();
      }

      if (mounted) {
        _allProperties = properties;
        _scoreCache = newCache;
        setState(() => _isLoading = false);
        await _rebuildMarkersFromCache();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка обновления меток'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Применяет активный фильтр к кэшу и перерисовывает маркеры без сетевого запроса.
  Future<void> _rebuildMarkersFromCache() async {
    final properties = _activeFilter.apply(
      _allProperties,
      scoreOf: (id) => _scoreCache[id]?.totalScore,
    );
    final Map<String, Uint8List> iconCache = {};

    final List<Future<PlacemarkMapObject>> markerFutures = properties.map((property) async {
      final scored = _scoreCache[property.id];
      final markerColor = scored != null ? scored.flutterColor : _primaryOrange;
      final score = scored?.totalScore;

      final cacheKey = '${markerColor.toARGB32()}_$score';
      Uint8List? iconBytes = iconCache[cacheKey];
      if (iconBytes == null) {
        iconBytes = await _buildMarkerIcon(markerColor, score);
        iconCache[cacheKey] = iconBytes;
      }

      return PlacemarkMapObject(
        mapId: MapObjectId('property_${property.id}'),
        point: Point(latitude: property.latitude, longitude: property.longitude),
        opacity: 1,
        icon: PlacemarkIcon.single(
          PlacemarkIconStyle(image: BitmapDescriptor.fromBytes(iconBytes), scale: 1.0),
        ),
        onTap: (PlacemarkMapObject self, Point point) => _showPropertyDetails(property),
      );
    }).toList();

    final placemarks = await Future.wait(markerFutures);

    final clusterizedCollection = ClusterizedPlacemarkCollection(
      mapId: const MapObjectId('clusterized_collection'),
      placemarks: placemarks,
      radius: 40,
      minZoom: 15,
      onClusterAdded: (ClusterizedPlacemarkCollection self, Cluster cluster) async {
        return cluster.copyWith(
          appearance: cluster.appearance.copyWith(
            opacity: 1.0,
            icon: PlacemarkIcon.single(
              PlacemarkIconStyle(
                image: BitmapDescriptor.fromBytes(await _buildClusterIcon(cluster.size)),
                scale: 1.0,
              ),
            ),
          ),
        );
      },
      onClusterTap: (ClusterizedPlacemarkCollection self, Cluster cluster) {
        mapController.moveCamera(
          CameraUpdate.zoomIn(),
          animation: const MapAnimation(type: MapAnimationType.linear, duration: 0.3),
        );
      },
    );

    if (mounted) setState(() => mapObjects = [clusterizedCollection]);
  }

  // Генерация цветного маркера с баллом скоринга
  Future<Uint8List> _buildMarkerIcon(Color color, int? score) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(120, 120);

    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final borderPaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 8;

    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width / 2, paint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width / 2 - 4, borderPaint);

    if (score != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: '$score%',
          style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _buildClusterIcon(int clusterSize) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(140, 140);
    
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
      
    final borderPaint = Paint()
      ..color = const Color(0xFFFF8C00) // _primaryOrange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;
      
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width / 2, paint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width / 2 - borderPaint.strokeWidth / 2, borderPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: clusterSize.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 60,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  void _showPropertyDetails(Property property) {
    final scored = _scoreCache[property.id];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Бейджик скоринга
              if (scored != null) ...
                [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: scored.flutterColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: scored.flutterColor.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, color: scored.flutterColor, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '${scored.totalScore}% — ${scored.matchLabel}',
                          style: TextStyle(color: scored.flutterColor, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              Text(
                property.title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${property.pricePerMonth} ₽ / мес',
                style: TextStyle(fontSize: 18, color: _primaryOrange, fontWeight: FontWeight.bold),
              ),
              if (scored != null) ...
                [
                  const SizedBox(height: 12),
                  _buildScoreBar('Финансы', scored.financialScore, 20),
                  _buildScoreBar('Технические', scored.technicalScore, 20),
                  _buildScoreBar('Конкуренты', scored.competitorScore, 40),
                  _buildScoreBar('Синергия', scored.synergyScore, 15),
                  _buildScoreBar('Транспорт', scored.transportScore, 5),
                  if (scored.breakdown?.transport != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '5 баллов отведены на доступ к транспорту: '
                        '${scored.breakdown!.transport!.reason ?? scored.breakdown!.transport!.typeLabel}.',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                      ),
                    ),
                ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PropertyDetailsScreen(
                          property: property,
                          scoredProperty: scored,
                          profileId: _activeProfile?.id,
                          desiredNeighborNames:
                              _activeProfile?.desiredNeighborNames ?? const [],
                          isLandlordMode: widget.isLandlordMode,
                        ),
                      ),
                    );
                    if (result is PropertyDetailsFocusResult) {
                      _focusCameraOn(result.latitude, result.longitude);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Подробнее',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  /// Плавно перемещает камеру к выбранному POI и доводит зум до улицы. Так
  /// MapScreen реагирует, когда пользователь тапнул конкретного конкурента
  /// или соседа в шторке PropertyDetailsScreen-а.
  void _focusCameraOn(double lat, double lon) {
    if (!_mapControllerReady) return;
    mapController.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: Point(latitude: lat, longitude: lon), zoom: 17),
      ),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 0.6),
    );
  }

  Widget _buildScoreBar(String label, int score, int max) {
    final pct = max > 0 ? score / max : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0),
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(
                  pct > 0.7 ? const Color(0xFF22C55E) : pct > 0.4 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444),
                ),
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$score/$max', style: const TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _applyFilter(PropertyFilter filter) async {
    setState(() => _activeFilter = filter);
    await _rebuildMarkersFromCache();
  }

  void _showFilterSheet() {
    double? minPrice = _activeFilter.minPrice;
    double? maxPrice = _activeFilter.maxPrice;
    double? minArea  = _activeFilter.minArea;
    double? maxArea  = _activeFilter.maxArea;
    Set<ScoreBucket> selectedBuckets = Set.from(_activeFilter.scoreBuckets);
    final bool hasScoring = _activeProfile != null && _scoreCache.isNotEmpty;

    final minPriceCtrl = TextEditingController(text: minPrice?.toInt().toString() ?? '');
    final maxPriceCtrl = TextEditingController(text: maxPrice?.toInt().toString() ?? '');
    final minAreaCtrl  = TextEditingController(text: minArea?.toInt().toString() ?? '');
    final maxAreaCtrl  = TextEditingController(text: maxArea?.toInt().toString() ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Заголовок ──────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Фильтры',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: () => setSheet(() {
                        minPrice = maxPrice = minArea = maxArea = null;
                        selectedBuckets = {};
                        minPriceCtrl.clear(); maxPriceCtrl.clear();
                        minAreaCtrl.clear();  maxAreaCtrl.clear();
                      }),
                      child: const Text('Сбросить', style: TextStyle(color: Colors.grey)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Цена ───────────────────────────────────────────────
                const Text('Цена (₽/мес)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _filterTextField(minPriceCtrl, 'от', isNumeric: true,
                      onChanged: (v) => minPrice = double.tryParse(v))),
                  const SizedBox(width: 12),
                  Expanded(child: _filterTextField(maxPriceCtrl, 'до', isNumeric: true,
                      onChanged: (v) => maxPrice = double.tryParse(v))),
                ]),
                const SizedBox(height: 16),

                // ── Площадь ────────────────────────────────────────────
                const Text('Площадь (м²)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _filterTextField(minAreaCtrl, 'от', isNumeric: true,
                      onChanged: (v) => minArea = double.tryParse(v))),
                  const SizedBox(width: 12),
                  Expanded(child: _filterTextField(maxAreaCtrl, 'до', isNumeric: true,
                      onChanged: (v) => maxArea = double.tryParse(v))),
                ]),
                const SizedBox(height: 16),

                // ── Оценка соответствия ────────────────────────────────
                if (hasScoring) ...[
                  const Text('Оценка соответствия',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _scoreBucketButton(
                          label: 'Низкая',
                          range: '0–40',
                          color: const Color(0xFFEF4444),
                          selected: selectedBuckets.contains(ScoreBucket.low),
                          onTap: () => setSheet(() {
                            selectedBuckets.contains(ScoreBucket.low)
                                ? selectedBuckets.remove(ScoreBucket.low)
                                : selectedBuckets.add(ScoreBucket.low);
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _scoreBucketButton(
                          label: 'Средняя',
                          range: '40–80',
                          color: const Color(0xFFF59E0B),
                          selected: selectedBuckets.contains(ScoreBucket.medium),
                          onTap: () => setSheet(() {
                            selectedBuckets.contains(ScoreBucket.medium)
                                ? selectedBuckets.remove(ScoreBucket.medium)
                                : selectedBuckets.add(ScoreBucket.medium);
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _scoreBucketButton(
                          label: 'Высокая',
                          range: '80+',
                          color: const Color(0xFF22C55E),
                          selected: selectedBuckets.contains(ScoreBucket.high),
                          onTap: () => setSheet(() {
                            selectedBuckets.contains(ScoreBucket.high)
                                ? selectedBuckets.remove(ScoreBucket.high)
                                : selectedBuckets.add(ScoreBucket.high);
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Применить ──────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _applyFilter(PropertyFilter(
                        minPrice: minPrice,
                        maxPrice: maxPrice,
                        minArea:  minArea,
                        maxArea:  maxArea,
                        scoreBuckets: selectedBuckets,
                      ));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Применить',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterTextField(
    TextEditingController ctrl,
    String hint, {
    bool isNumeric = false,
    required Function(String) onChanged,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFF8C00), width: 1.5)),
      ),
    );
  }

  Widget _scoreBucketButton({
    required String label,
    required String range,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? color : color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.45),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                range,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.9)
                      : color.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. КАРТА
          YandexMap(
            mapObjects: mapObjects,
            onMapCreated: (YandexMapController controller) {
              mapController = controller;
              _mapControllerReady = true;
              // Применяем стиль, только если он не пустой
              if (_mapStyle.length > 5) {
                mapController.setMapStyle(_mapStyle);
              }
              mapController.moveCamera(
                CameraUpdate.newCameraPosition(
                  const CameraPosition(
                    target: Point(latitude: 55.751244, longitude: 37.618423),
                    zoom: 12.0,
                  ),
                ),
              );
            },
          ),

          // 2. КНОПКА ОБНОВЛЕНИЯ (Справа внизу, над панелью)
          Positioned(
            right: 16,
            bottom: 120,
            child: FloatingActionButton(
              heroTag: 'refresh_map',
              backgroundColor: Colors.white,
              onPressed: _isLoading ? null : _loadProperties,
              child: _isLoading
                  ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)
              )
                  : const Icon(Icons.refresh, color: Colors.black),
            ),
          ),

          // 3. ВЕРХНЯЯ ПАНЕЛЬ (поиск + фильтр доступны и арендатору, и владельцу)
          SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Строка поиска + кнопка фильтров
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 5))],
                            ),
                            child: TextField(
                              controller: _searchController,
                              onChanged: _onSearchChanged,
                              onSubmitted: _performAddressSearch,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: 'Поиск адреса...',
                                hintStyle: const TextStyle(color: Colors.black38),
                                prefixIcon: const Icon(Icons.search, color: Colors.black54),
                                suffixIcon: _isSearchingAddress
                                    ? const Padding(
                                        padding: EdgeInsets.all(12.0),
                                        child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      )
                                    : _searchController.text.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear, color: Colors.grey),
                                            onPressed: () {
                                              _searchController.clear();
                                              _onSearchChanged('');
                                            },
                                          )
                                        : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: _activeFilter.isActive ? _primaryOrange : Colors.black87,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 5))],
                              ),
                              child: IconButton(
                                icon: Icon(Icons.tune,
                                    color: _activeFilter.isActive ? Colors.white : _primaryOrange),
                                onPressed: _showFilterSheet,
                                padding: const EdgeInsets.all(12),
                              ),
                            ),
                            if (_activeFilter.isActive)
                              Positioned(
                                top: -4,
                                right: -4,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                  child: Center(
                                    child: Text('${_activeFilter.activeCount}',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    // Подсказки автодополнения по адресу
                    if (_searchSuggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 260),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: _searchSuggestions.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = _searchSuggestions[index];
                              return ListTile(
                                dense: true,
                                leading: Icon(Icons.location_on_outlined,
                                    color: _primaryOrange, size: 20),
                                title: Text(item.title,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                subtitle: (item.subtitle != null && item.subtitle!.isNotEmpty)
                                    ? Text(item.subtitle!,
                                        style: const TextStyle(fontSize: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)
                                    : null,
                                onTap: () => _onSuggestionTapped(item),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                    // Dropdown выбора профиля поиска (только для арендатора)
                    if (!widget.isLandlordMode && _myProfiles.isNotEmpty) ...
                      [
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              isExpanded: true,
                              value: _activeProfile?.id,
                              icon: Icon(Icons.keyboard_arrow_down_rounded, color: _primaryOrange),
                              hint: const Text('Выбрать проект поиска', style: TextStyle(fontSize: 13)),
                              style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600),
                              items: _myProfiles.map((p) {
                                return DropdownMenuItem<int>(
                                  value: p.id,
                                  child: Row(
                                    children: [
                                      Icon(Icons.manage_search_rounded, size: 16, color: _primaryOrange),
                                      const SizedBox(width: 6),
                                      Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val == null) return;
                                setState(() {
                                  _activeProfile = _myProfiles.firstWhere((p) => p.id == val);
                                });
                                _loadProperties();
                              },
                            ),
                          ),
                        ),
                      ],
                    // ── Счётчик результатов при активном фильтре ──────
                    if (_activeFilter.isActive) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _primaryOrange,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 3))],
                            ),
                            child: Text(
                              '${_activeFilter.apply(_allProperties, scoreOf: (id) => _scoreCache[id]?.totalScore).length} из ${_allProperties.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _applyFilter(PropertyFilter.empty),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
                              ),
                              child: const Text('Сбросить', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}