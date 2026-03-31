import 'package:flutter/material.dart';

import '../../../domain/property.dart';
import '../../../services/application_service.dart';
import '../../../services/favorite_service.dart';


class PropertyDetailsScreen extends StatefulWidget {
  final Property property;
  final bool isLandlordMode; // <-- 1. ДОБАВИТЬ ЭТУ СТРОКУ

  const PropertyDetailsScreen({
    super.key,
    required this.property,
    this.isLandlordMode = false, // <-- 2. ДОБАВИТЬ ЭТУ СТРОКУ (по умолчанию false)
  });

  @override
  State<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends State<PropertyDetailsScreen> {
  final Color primaryOrange = const Color(0xFFFF8C00);

  bool _isFavorite = false;
  bool _isLoadingFavorite = false;
  bool _isCheckingInitialState = true; // Индикатор начальной проверки лайка

  @override
  void initState() {
    super.initState();
    _checkIfFavorite(); // Проверяем статус при открытии экрана
  }

  // --- НОВЫЙ МЕТОД: Проверяем, в избранном ли мы уже ---
  Future<void> _checkIfFavorite() async {
    final favorites = await FavoriteService().getMyFavorites();

    if (!mounted) return;

    // Ищем, есть ли ID текущего помещения в списке избранных
    final isFav = favorites.any((favProperty) => favProperty.id == widget.property.id);

    setState(() {
      _isFavorite = isFav;
      _isCheckingInitialState = false;
    });
  }

  // Метод для переключения состояния "Избранное"
  Future<void> _toggleFavorite() async {
    setState(() => _isLoadingFavorite = true);

    final success = _isFavorite
        ? await FavoriteService().removeFromFavorites(widget.property.id)
        : await FavoriteService().addToFavorites(widget.property.id);

    setState(() => _isLoadingFavorite = false);

    if (success) {
      setState(() {
        _isFavorite = !_isFavorite;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFavorite ? 'Добавлено в избранное' : 'Удалено из избранного'),
          duration: const Duration(seconds: 1),
          backgroundColor: _isFavorite ? Colors.green : Colors.grey[800],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка сети'), backgroundColor: Colors.red),
      );
    }
  }

  void _showApplicationSheet(BuildContext context, Property property) {
    final TextEditingController letterController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateSheet) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Оставить заявку', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: letterController,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: 'Напишите сопроводительное письмо арендодателю...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primaryOrange, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                        final text = letterController.text.trim();
                        if (text.isEmpty) return;

                        setStateSheet(() => isSubmitting = true);
                        final success = await ApplicationService().createApplication(property.id, text);
                        setStateSheet(() => isSubmitting = false);

                        if (success) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Заявка успешно отправлена!'), backgroundColor: Colors.green),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryOrange,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isSubmitting
                          ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Отправить', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('Детали помещения', style: TextStyle(color: Colors.black)),
        actions: [
          // КНОПКА "ИЗБРАННОЕ"
          IconButton(
            icon: _isCheckingInitialState || _isLoadingFavorite
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite ? primaryOrange : Colors.black,
            ),
            onPressed: (_isCheckingInitialState || _isLoadingFavorite) ? null : _toggleFavorite,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.storefront, size: 80, color: Colors.black26),
            ),
            const SizedBox(height: 24),
            Text('${widget.property.pricePerMonth} ₽ / мес', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: primaryOrange)),
            const SizedBox(height: 8),
            Text(widget.property.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.black54, size: 18),
                const SizedBox(width: 4),
                Expanded(child: Text(widget.property.address, style: const TextStyle(color: Colors.black54, fontSize: 16))),
              ],
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildSpecChip(Icons.bolt, '${widget.property.powerKw} кВт'),
                if (widget.property.hasWater) _buildSpecChip(Icons.water_drop, 'Вода'),
                if (widget.property.hasVentilation) _buildSpecChip(Icons.air, 'Вытяжка'),
                if (widget.property.hasSeparateEntrance) _buildSpecChip(Icons.door_front_door, 'Отд. вход'),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Описание', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(widget.property.description, style: const TextStyle(fontSize: 16, height: 1.5, color: Colors.black87)),
            const SizedBox(height: 100),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ElevatedButton(
          onPressed: () => _showApplicationSheet(context, widget.property),
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