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
  Timer? _reverseGeocodeDebounce;

  List<SuggestItem> _suggestions = [];
  bool _isSearching = false;

  // Текущий адрес метки (обратное геокодирование)
  String? _currentAddress;
  bool _isResolvingAddress = false;

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    _reverseGeocodeDebounce?.cancel();
    super.dispose();
  }

  // ОБРАТНОЕ ГЕОКОДИРОВАНИЕ: по координатам -> адрес
  Future<void> _reverseGeocode(Point point) async {
    if (!mounted) return;
    setState(() => _isResolvingAddress = true);

    try {
      final searchTuple = await YandexSearch.searchByPoint(
        point: point,
        zoom: 17,
        searchOptions: const SearchOptions(
          searchType: SearchType.geo,
          geometry: false,
        ),
      );
      final result = await searchTuple.$2;

      String? address;
      if (result != null && result.items != null && result.items!.isNotEmpty) {
        final topItem = result.items!.first;
        // 1) Полный форматированный адрес (приоритет — на русском)
        address = topItem.toponymMetadata?.address.formattedAddress;
        // 2) Фоллбек на имя топонима
        address ??= topItem.name;
      }

      if (!mounted) return;
      setState(() {
        _currentAddress = (address != null && address.trim().isNotEmpty)
            ? address.trim()
            : null;
        _isResolvingAddress = false;
      });
    } catch (e) {
      debugPrint('Ошибка обратного геокодирования: $e');
      if (mounted) {
        setState(() {
          _currentAddress = null;
          _isResolvingAddress = false;
        });
      }
    }
  }

  void _scheduleReverseGeocode(Point point) {
    _reverseGeocodeDebounce?.cancel();
    _reverseGeocodeDebounce = Timer(const Duration(milliseconds: 400), () {
      _reverseGeocode(point);
    });
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

        // ИСПРАВЛЕНИЕ 1: Дожидаемся ответа и распаковываем
        final suggestTuple = await YandexSuggest.getSuggestions(
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
        final resultFuture = suggestTuple.$2;

        final result = await resultFuture;
        if (result == null) return;

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
    await _performSearch(fullAddress);
  }

  // 3. МЕТОД ПРЯМОГО ПОИСКА
  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _suggestions.clear();
      _isSearching = true;
    });

    try {
      // ИСПРАВЛЕНИЕ 3: Распаковка кортежа для Search
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
      final searchResultFuture = searchTuple.$2;

      final result = await searchResultFuture;
      if (result == null) {
        if (mounted) setState(() => _isSearching = false);
        return;
      }

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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Адрес не найден. Попробуйте уточнить запрос.')),
          );
        }
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
              if (finished) {
                _scheduleReverseGeocode(cameraPosition.target);
              }
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
                    onSubmitted: _performSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Поиск адреса...',
                      prefixIcon: GestureDetector(
                        onTap: () => _performSearch(_searchController.text),
                        child: const Icon(Icons.search, color: Colors.grey),
                      ),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.location_on, color: _primaryOrange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _isResolvingAddress
                            ? Row(
                                children: const [
                                  SizedBox(
                                    height: 14,
                                    width: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                  SizedBox(width: 8),
                                  Text('Определяем адрес...',
                                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                                ],
                              )
                            : Text(
                                _currentAddress ?? 'Передвиньте карту, чтобы выбрать точку',
                                style: TextStyle(
                                  color: _currentAddress != null ? Colors.black87 : Colors.grey,
                                  fontSize: 13,
                                  fontWeight: _currentAddress != null
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isMoving ? null : () {
                        Navigator.pop(context, {
                          'latitude': _currentCameraPosition.latitude,
                          'longitude': _currentCameraPosition.longitude,
                          'address': _currentAddress,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
