import 'package:flutter/material.dart';
import 'package:frontend/screens/property.dart';
import 'property.dart';

class PropertyDetailsScreen extends StatelessWidget {
  final Property property;

  const PropertyDetailsScreen({super.key, required this.property});

  @override
  Widget build(BuildContext context) {
    final Color primaryOrange = const Color(0xFFFF8C00);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('Детали помещения', style: TextStyle(color: Colors.black)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заглушка для фото (пока в БД массив images пустой)
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.storefront, size: 80, color: Colors.black26),
            ),
            const SizedBox(height: 24),

            // Цена и Заголовок
            Text(
              '${property.pricePerMonth} ₽ / мес',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: primaryOrange),
            ),
            const SizedBox(height: 8),
            Text(
              property.title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.black54, size: 18),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(property.address, style: const TextStyle(color: Colors.black54, fontSize: 16)),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Плашки характеристик
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildSpecChip(Icons.bolt, '${property.powerKw} кВт'),
                if (property.hasWater) _buildSpecChip(Icons.water_drop, 'Вода'),
                if (property.hasVentilation) _buildSpecChip(Icons.air, 'Вытяжка'),
                if (property.hasSeparateEntrance) _buildSpecChip(Icons.door_front_door, 'Отд. вход'),
              ],
            ),
            const SizedBox(height: 24),

            // Описание
            const Text('Описание', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              property.description,
              style: const TextStyle(fontSize: 16, height: 1.5, color: Colors.black87),
            ),

            // Отступ снизу, чтобы плавающая кнопка не перекрывала текст
            const SizedBox(height: 100),
          ],
        ),
      ),

      // Плавающая кнопка заявки
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ElevatedButton(
          onPressed: () {
            // TODO: Открыть форму создания заявки
            print("Нажата кнопка заявки");
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('Оставить заявку', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  // Вспомогательный виджет для красивых бейджей характеристик
  Widget _buildSpecChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.black87),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}