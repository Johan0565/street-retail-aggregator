import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import 'package:geolocator/geolocator.dart';

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  late YandexMapController _mapController;
  final Color _primaryOrange = const Color(0xFFFF8C00);

  // По умолчанию центр Москвы
  Point _currentCameraPosition = const Point(latitude: 55.751244, longitude: 37.618423);
  bool _isMoving = false;

  // Контроллеры для поиска
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  List<SuggestItem> _suggestions = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }



  // 1. МЕТОД АВТОДОПОЛНЕНИЯ (SUGGEST)
  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _isSearching = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isSearching = true);

      try {
        final region = await _mapController.getVisibleRegion();

        // ИСПРАВЛЕНИЕ 1: Распаковка кортежа для Suggest
        final (session, resultFuture) = await YandexSuggest.getSuggestions(
          text: query,
          boundingBox: BoundingBox(
            southWest: region.bottomLeft,
            northEast: region.topRight,
          ),
          suggestOptions: const SuggestOptions(
            suggestType: SuggestType.geo,
            suggestWords: true,
          ),
        );

        final result = await resultFuture;

        if (result.error != null) {
          debugPrint('🚨 ОШИБКА SUGGEST: ${result.error}');
        }

        if (mounted) {
          setState(() {
            _suggestions = result.items ?? [];
            _isSearching = false;
          });
        }
      } catch (e) {
        debugPrint('Ошибка Suggest: $e');
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  // 2. МЕТОД ПОИСКА КООРДИНАТ ПО КЛИКУ НА ПОДСКАЗКУ
  Future<void> _onSuggestionTapped(SuggestItem item) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _searchController.text = item.title;
      _suggestions.clear();
      _isSearching = true;
    });

    // ИСПРАВЛЕНИЕ 2: item.subtitle — это просто строка, а не объект с .text
    final fullAddress = '${item.title} ${item.subtitle ?? ''}'.trim();

    try {
      // ИСПРАВЛЕНИЕ 3: Распаковка кортежа для Search
      final (searchSession, searchResultFuture) = await YandexSearch.searchByText(
        searchText: fullAddress,
        geometry: Geometry.fromBoundingBox(
          const BoundingBox(
            southWest: Point(latitude: -90, longitude: -180),
            northEast: Point(latitude: 90, longitude: 180),
          ),
        ),
        searchOptions: const SearchOptions(searchType: SearchType.geo),
      );

      final result = await searchResultFuture;

      Point? targetPoint;
      if (result.items != null && result.items!.isNotEmpty) {
        final topItem = result.items!.first;
        targetPoint = topItem.toponymMetadata?.balloonPoint ??
            (topItem.geometry.isNotEmpty ? topItem.geometry.first.point : null);
      }

      if (targetPoint != null) {
        _mapController.moveCamera(
          CameraUpdate.newCameraPosition(CameraPosition(target: targetPoint, zoom: 16)),
          animation: const MapAnimation(type: MapAnimationType.smooth, duration: 1.5),
        );
      } else {
        debugPrint('Координаты не найдены');
      }
    } catch (e) {
      debugPrint('Ошибка получения координат: $e');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Установите маркер', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Stack(
        children: [
          YandexMap(
            onMapCreated: (controller) {
              _mapController = controller;
              _mapController.moveCamera(
                  CameraUpdate.newCameraPosition(CameraPosition(target: _currentCameraPosition, zoom: 12))
              );

            },
            onCameraPositionChanged: (cameraPosition, reason, finished) {
              setState(() {
                _currentCameraPosition = cameraPosition.target;
                _isMoving = !finished;
              });
            },
          ),

          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36.0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                transform: Matrix4.translationValues(0, _isMoving ? -10 : 0, 0),
                child: Icon(Icons.location_on, size: 50, color: _primaryOrange),
              ),
            ),
          ),

          Positioned(
            top: 16, left: 16, right: 16,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Поиск адреса...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _isSearching
                          ? const Padding(padding: EdgeInsets.all(12.0), child: CircularProgressIndicator(strokeWidth: 2))
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),

                if (_suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 250),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _suggestions.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _suggestions[index];
                        return ListTile(
                          leading: const Icon(Icons.location_city, color: Colors.grey),
                          title: Text(item.title),
                          // ИСПРАВЛЕНИЕ 4: Правильное обращение к subtitle в UI
                          subtitle: item.subtitle != null && item.subtitle!.isNotEmpty
                              ? Text(item.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis)
                              : null,
                          onTap: () => _onSuggestionTapped(item),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),



          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: ElevatedButton(
                onPressed: _isMoving ? null : () {
                  Navigator.pop(context, {
                    'latitude': _currentCameraPosition.latitude,
                    'longitude': _currentCameraPosition.longitude,
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Сохранить координаты', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
