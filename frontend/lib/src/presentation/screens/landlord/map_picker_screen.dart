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

  Future<void> _moveToCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      Position position = await Geolocator.getCurrentPosition();
      final userPoint = Point(latitude: position.latitude, longitude: position.longitude);

      _mapController.moveCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: userPoint, zoom: 16)),
        animation: const MapAnimation(type: MapAnimationType.smooth, duration: 1.5),
      );
    } catch (e) {
      print('Ошибка локации: $e');
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
              _moveToCurrentLocation();
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
            bottom: 120, right: 16,
            child: FloatingActionButton(
              backgroundColor: Colors.white,
              onPressed: _moveToCurrentLocation,
              child: const Icon(Icons.my_location, color: Colors.black),
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
                  // Просто возвращаем точные координаты
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