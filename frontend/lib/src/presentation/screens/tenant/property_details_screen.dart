import 'package:flutter/material.dart';
import '../../../domain/property.dart';
import '../../../services/application_service.dart';
import '../../../services/favorite_service.dart';

class PropertyDetailsScreen extends StatefulWidget {
  final Property property;
  final bool isLandlordMode;

  const PropertyDetailsScreen({
    super.key,
    required this.property,
    this.isLandlordMode = false,
  });

  @override
  State<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends State<PropertyDetailsScreen> {
  final Color primaryOrange = const Color(0xFFFF8C00);

  bool _isFavorite = false;
  bool _isLoadingFavorite = false;
  bool _isCheckingInitialState = true;

  @override
  void initState() {
    super.initState();
    if (!widget.isLandlordMode) {
      _checkIfFavorite();
    } else {
      _isCheckingInitialState = false;
    }
  }

  Future<void> _checkIfFavorite() async {
    final favorites = await FavoriteService().getMyFavorites();
    if (!mounted) return;
    final isFav = favorites.any((favProperty) => favProperty.id == widget.property.id);
    setState(() {
      _isFavorite = isFav;
      _isCheckingInitialState = false;
    });
  }

  Future<void> _toggleFavorite() async {
    setState(() => _isLoadingFavorite = true);
    final success = _isFavorite
        ? await FavoriteService().removeFromFavorites(widget.property.id)
        : await FavoriteService().addToFavorites(widget.property.id);
    setState(() => _isLoadingFavorite = false);

    if (success) {
      setState(() => _isFavorite = !_isFavorite);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFavorite ? 'Добавлено в избранное' : 'Удалено из избранного'),
          duration: const Duration(seconds: 1),
          backgroundColor: _isFavorite ? Colors.green : Colors.grey[800],
        ),
      );
    }
  }

  // Маппинг английских Enum в русский текст
  String _translateEnum(String? value, Map<String, String> translations) {
    if (value == null) return 'Не указано';
    return translations[value] ?? value;
  }

  void _showApplicationSheet(BuildContext context, Property property) {
    final TextEditingController letterController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateSheet) {
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom, // Чтобы клавиатура не перекрывала
                  left: 24, right: 24, top: 24
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
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryOrange, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSubmitting ? null : () async {
                        final text = letterController.text.trim();
                        if (text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Напишите сообщение')));
                          return;
                        }

                        setStateSheet(() => isSubmitting = true);
                        final success = await ApplicationService().createApplication(property.id, text);
                        setStateSheet(() => isSubmitting = false);

                        if (success) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Заявка успешно отправлена!'), backgroundColor: Colors.green));
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка при отправке'), backgroundColor: Colors.red));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      child: isSubmitting
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Отправить', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  )
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
      backgroundColor: const Color(0xFFF4F5F7), // Светло-серый фон как в агрегаторах
      body: CustomScrollView(
        slivers: [
          // КРАСИВАЯ ШАПКА С ФОТОГРАФИЕЙ
          SliverAppBar(
            expandedHeight: 300.0,
            pinned: true,
            backgroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.black),
            actions: [
              if (!widget.isLandlordMode)
                IconButton(
                  icon: _isCheckingInitialState || _isLoadingFavorite
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : Icon(_isFavorite ? Icons.favorite : Icons.favorite_border, color: _isFavorite ? primaryOrange : Colors.black),
                  onPressed: (_isCheckingInitialState || _isLoadingFavorite) ? null : _toggleFavorite,
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: Colors.grey[300],
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const Center(child: Icon(Icons.image_outlined, size: 80, color: Colors.grey)),
                    // Градиент для читаемости кнопок сверху
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Colors.black.withOpacity(0.4), Colors.transparent, Colors.transparent],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ТЕЛО СТРАНИЦЫ
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. ЗАГОЛОВОК И ЦЕНА
                  Text('${widget.property.pricePerMonth} ₽ / мес', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: primaryOrange)),
                  const SizedBox(height: 8),
                  Text(widget.property.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.2)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on, color: Colors.grey, size: 20),
                      const SizedBox(width: 4),
                      Expanded(child: Text(widget.property.address, style: const TextStyle(color: Colors.black87, fontSize: 15))),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 2. ГЛАВНЫЕ ХАРАКТЕРИСТИКИ (Грид)
                  _buildSectionCard(
                    title: 'О помещении',
                    child: Column(
                      children: [
                        _buildInfoRow('Тип недвижимости', _translateEnum(widget.property.propertyType, {'OFFICE':'Офис', 'RETAIL':'Стрит-ритейл', 'WAREHOUSE':'Склад', 'PSN':'ПСН', 'CATERING':'Общепит'})),
                        const Divider(height: 24),
                        _buildInfoRow('Общая площадь', '${widget.property.areaSqm} м²'),
                        if (widget.property.cadastralNumber != null && widget.property.cadastralNumber!.isNotEmpty) ...[
                          const Divider(height: 24),
                          _buildInfoRow('Кадастровый номер', widget.property.cadastralNumber!),
                        ]
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. БЫСТРЫЕ ТЕГИ
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      _buildSpecChip(Icons.bolt, '${widget.property.powerKw} кВт'),
                      if (widget.property.hasWater) _buildSpecChip(Icons.water_drop, 'Мокрая точка'),
                      if (widget.property.hasVentilation) _buildSpecChip(Icons.air, 'Вытяжка'),
                      if (widget.property.hasSeparateEntrance) _buildSpecChip(Icons.door_front_door, 'Отд. вход'),
                      if (widget.property.isOccupied == true) _buildSpecChip(Icons.people, 'Сейчас сдано (ГАБ)'),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 4. ТЕХНИЧЕСКИЕ ДЕТАЛИ
                  _buildSectionCard(
                    title: 'Условия и удобства',
                    child: Column(
                      children: [
                        _buildInfoRow('Доступ', _translateEnum(widget.property.accessType, {'FREE':'Круглосуточно (24/7)', 'SCHEDULE':'По расписанию', 'PASS':'По пропускам'})),
                        const Divider(height: 24),
                        _buildInfoRow('Отопление', _translateEnum(widget.property.heatingType, {'CENTRAL':'Центральное', 'AUTONOMOUS':'Автономное', 'NONE':'Нет отопления'})),
                        const Divider(height: 24),
                        _buildInfoRow('Состояние', _translateEnum(widget.property.furnitureState, {'EMPTY':'Пустое', 'FURNISHED':'С мебелью', 'READY_BUSINESS':'Готовый бизнес'})),
                        const Divider(height: 24),
                        _buildInfoRow('Ремонт', _translateEnum(widget.property.repairState, {'PRE_FINISHING':'Под чистовую', 'TYPICAL':'Типовой', 'DESIGNER':'Дизайнерский', 'SHELL_AND_CORE':'Требует ремонта'})),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 5. ОПИСАНИЕ
                  _buildSectionCard(
                    title: 'Описание',
                    child: Text(widget.property.description, style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // КНОПКА ЗАЯВКИ СНИЗУ (только для арендатора)
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: !widget.isLandlordMode
          ? Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]),
        child: ElevatedButton(
          onPressed: () => _showApplicationSheet(context, widget.property),
          style: ElevatedButton.styleFrom(backgroundColor: primaryOrange, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('Оставить заявку', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      )
          : null,
    );
  }

  // Виджет Карточки для Блоков (Стиль Домклика)
  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  // Виджет строки "Ключ - Значение"
  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 15)),
        const SizedBox(width: 16),
        Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15), textAlign: TextAlign.right)),
      ],
    );
  }

  // Виджет бейджика
  Widget _buildSpecChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: primaryOrange),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}