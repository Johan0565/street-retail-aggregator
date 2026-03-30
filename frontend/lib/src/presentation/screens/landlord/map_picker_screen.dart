import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import 'package:geolocator/geolocator.dart'; // Добавили геолокацию

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  late YandexMapController _mapController;
  final Color _primaryOrange = const Color(0xFFFF8C00);
  final TextEditingController _searchController = TextEditingController(); // Контроллер для поиска

  Point _currentCameraPosition = const Point(latitude: 55.751244, longitude: 37.618423);
  String _currentAddress = 'Определение адреса...';
  bool _isMoving = false;

  // --- 1. ПЕРЕХОД К ТЕКУЩЕЙ ГЕОПОЗИЦИИ ---
  Future<void> _moveToCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return; // Если GPS выключен

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    // Получаем текущие координаты
    Position position = await Geolocator.getCurrentPosition();
    final userPoint = Point(latitude: position.latitude, longitude: position.longitude);

    // Двигаем камеру туда
    _mapController.moveCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: userPoint, zoom: 16)),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 1.5),
    );
  }

  // --- 2. ПОИСК АДРЕСА ПО ТЕКСТУ (Строка поиска) ---
  Future<void> _searchByText(String text) async {
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus(); // Скрываем клавиатуру

    try {
      final resultWithSession = await YandexSearch.searchByText(
        searchText: text,
        geometry: Geometry.fromBoundingBox(const BoundingBox(
          northEast: Point(latitude: 71.0, longitude: -170.0),
          southWest: Point(latitude: 41.0, longitude: 19.0),
        )),
        searchOptions: const SearchOptions(searchType: SearchType.geo),
      );

      final result = await resultWithSession.$2;

      if (result.items != null && result.items!.isNotEmpty) {
        // Берем координаты первого найденного адреса
        final point = result.items!.first.toponymMetadata?.balloonPoint;
        if (point != null) {
          _mapController.moveCamera(
            CameraUpdate.newCameraPosition(CameraPosition(target: point, zoom: 16)),
            animation: const MapAnimation(type: MapAnimationType.smooth, duration: 1.5),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ничего не найдено')));
      }
    } catch (e) {
      print('Ошибка поиска: $e');
    }
  }

  // --- 3. ОПРЕДЕЛЕНИЕ АДРЕСА ПОД МАРКЕРОМ ---
  Future<void> _fetchAddress(Point point) async {
    setState(() => _currentAddress = 'Загрузка...');
    try {
      final resultWithSession = await YandexSearch.searchByPoint(
        point: point,
        searchOptions: const SearchOptions(searchType: SearchType.geo),
      );
      final result = await resultWithSession.$2;

      if (result.items != null && result.items!.isNotEmpty) {
        setState(() {
          _currentAddress = result.items!.first.toponymMetadata?.address.formattedAddress ?? 'Адрес не найден';
        });
      } else {
        setState(() => _currentAddress = 'Адрес не найден');
      }
    } catch (e) {
      setState(() => _currentAddress = 'Ошибка получения адреса');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Укажите расположение', style: TextStyle(color: Colors.black, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Stack(
        children: [
          // КАРТА
          YandexMap(
            onMapCreated: (controller) {
              _mapController = controller;
              _moveToCurrentLocation(); // Прыгаем на пользователя при открытии!
            },
            onCameraPositionChanged: (cameraPosition, reason, finished) {
              setState(() {
                _currentCameraPosition = cameraPosition.target;
                _isMoving = !finished;
              });
              if (finished) _fetchAddress(cameraPosition.target);
            },
          ),

          // ЦЕНТРАЛЬНЫЙ МАРКЕР
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

          // ПОИСКОВАЯ СТРОКА СВЕРХУ
          Positioned(
            top: 16, left: 16, right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: TextField(
                controller: _searchController,
                onSubmitted: _searchByText,
                decoration: InputDecoration(
                  hintText: 'Введите город, улицу, дом...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, color: Colors.grey),
                    onPressed: () {
                      _searchController.clear();
                      FocusScope.of(context).unfocus();
                    },
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),

          // КНОПКА "МОЕ МЕСТОПОЛОЖЕНИЕ"
          Positioned(
            bottom: 220, right: 16,
            child: FloatingActionButton(
              heroTag: 'myLocation',
              backgroundColor: Colors.white,
              onPressed: _moveToCurrentLocation,
              child: const Icon(Icons.my_location, color: Colors.black),
            ),
          ),

          // ПАНЕЛЬ С АДРЕСОМ СНИЗУ
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 5))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Выбранный адрес:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 8),
                  Text(_currentAddress, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 20),
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
                      child: const Text('Выбрать эту точку', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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