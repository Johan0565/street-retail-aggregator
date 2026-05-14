import 'dart:async';

import 'package:flutter/material.dart';
import '../../../domain/property.dart';
import '../../../domain/search_profile.dart';
import '../../../services/application_service.dart';
import '../../../services/favorite_service.dart';
import '../../../services/analytics_service.dart';
import '../../../services/image_helper.dart';
import '../../../services/infrastructure_service.dart';
import '../../../services/property_service.dart';

class PropertyDetailsScreen extends StatefulWidget {
  final Property property;
  final bool isLandlordMode;
  final ScoredProperty? scoredProperty; // необязательный результат скоринга
  /// ID проекта поиска, под который строится скоринг и AI-отчёт. Если не
  /// задан — бэкенд использует первый активный проект арендатора.
  final int? profileId;

  const PropertyDetailsScreen({
    super.key,
    required this.property,
    this.isLandlordMode = false,
    this.scoredProperty,
    this.profileId,
  });

  @override
  State<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends State<PropertyDetailsScreen> {
  final Color primaryOrange = const Color(0xFFFF8C00);

  bool _isFavorite = false;
  bool _isLoadingFavorite = false;
  bool _isCheckingInitialState = true;
  Future<List<PoiDto>>? _poiFuture;

  final PageController _photoController = PageController();
  int _photoIndex = 0;

  // Скоринг, подгружаемый с бэкенда (когда scoredProperty не передан извне)
  ScoredProperty? _loadedScore;
  bool _isLoadingScore = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isLandlordMode) {
      _checkIfFavorite();
      AnalyticsService().logPropertyView(widget.property.id);
      // скор подгружается только явно (кнопкой), чтобы не тратить 2GIS-лимиты при каждом открытии
    } else {
      _isCheckingInitialState = false;
    }
    _poiFuture = InfrastructureService().getInfrastructureNearby(
      widget.property.latitude,
      widget.property.longitude,
    );
  }

  Future<void> _loadScore() async {
    setState(() => _isLoadingScore = true);
    final score = await PropertyService()
        .scoreProperty(widget.property.id, profileId: widget.profileId);
    if (!mounted) return;
    setState(() {
      _loadedScore = score;
      _isLoadingScore = false;
    });
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

  // Карточка скоринга — показывает бейджик и 4 полоски прогресса
  Widget _buildScoringCard(ScoredProperty scored) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scored.flutterColor.withOpacity(0.08), scored.flutterColor.withOpacity(0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scored.flutterColor.withOpacity(0.25), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: scored.flutterColor, size: 18),
              const SizedBox(width: 8),
              Text(
                '${scored.totalScore}% — ${scored.matchLabel}',
                style: TextStyle(color: scored.flutterColor, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _scoreBar('Финансовый', scored.financialScore, 30),
          _scoreBar('Технический', scored.technicalScore, 20),
          _scoreBar('Конкуренты', scored.competitorScore, 30),
          _scoreBar('Синергия', scored.synergyScore, 20),
        ],
      ),
    );
  }

  Widget _buildScoringLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            'Анализируем конкурентов поблизости...',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _scoreBar(String label, int score, int max) {
    final pct = max > 0 ? score / max : 0.0;
    final color = pct > 0.7
        ? const Color(0xFF22C55E)
        : pct > 0.4
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0),
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 10,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$score/$max', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black45)),
        ],
      ),
    );
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
              background: _buildPhotoHeader(),
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
                  if (widget.property.status == 'ARCHIVED')
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.red[700]),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Это помещение снято с публикации и недоступно для аренды.',
                              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
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
                  // Блок скоринга
                  if (_isLoadingScore) ...[
                    const SizedBox(height: 16),
                    _buildScoringLoadingCard(),
                  ] else if ((widget.scoredProperty ?? _loadedScore) != null) ...[
                    const SizedBox(height: 16),
                    _buildScoringCard((widget.scoredProperty ?? _loadedScore)!),
                    const SizedBox(height: 10),
                    _buildCompetitorsButton((widget.scoredProperty ?? _loadedScore)!),
                    const SizedBox(height: 10),
                    _buildAiExplainButton(),
                  ] else if (!widget.isLandlordMode) ...[
                    const SizedBox(height: 16),
                    _buildScoreRequestButton(),
                  ],
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
                      if (widget.property.ceilingHeight != null)
                        _buildSpecChip(Icons.height, '${widget.property.ceilingHeight} м потолки'),
                      if (widget.property.hasWater) _buildSpecChip(Icons.water_drop, 'Мокрая точка'),
                      if (widget.property.hasVentilation) _buildSpecChip(Icons.air, 'Вытяжка'),
                      if (widget.property.hasSeparateEntrance) _buildSpecChip(Icons.door_front_door, 'Отд. вход'),
                      if (widget.property.hasWc) _buildSpecChip(Icons.wc, 'Санузел'),
                      if (widget.property.hasParking) _buildSpecChip(Icons.local_parking, 'Парковка'),
                      if (widget.property.hasLoadingZone) _buildSpecChip(Icons.local_shipping, 'Зона разгрузки'),
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
                  const SizedBox(height: 16),
                  
                  // 6. ИНФРАСТРУКТУРА
                  _buildSectionCard(
                    title: 'Что рядом',
                    child: _buildInfrastructureSection(),
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
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))]),
        child: ElevatedButton(
          onPressed: widget.property.status == 'ARCHIVED' ? null : () => _showApplicationSheet(context, widget.property),
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.property.status == 'ARCHIVED' ? Colors.grey : primaryOrange,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            widget.property.status == 'ARCHIVED' ? 'Недоступно' : 'Оставить заявку',
            style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      )
          : null,
    );
  }

  Widget _buildPhotoHeader() {
    final images = widget.property.images;
    if (images.isEmpty) {
      return Container(
        color: Colors.grey[300],
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Center(child: Icon(Icons.image_outlined, size: 80, color: Colors.grey)),
            _headerGradient(),
          ],
        ),
      );
    }

    // Главное фото — первым в списке.
    final ordered = [
      ...images.where((i) => i.isMain),
      ...images.where((i) => !i.isMain),
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _photoController,
          itemCount: ordered.length,
          onPageChanged: (i) => setState(() => _photoIndex = i),
          itemBuilder: (ctx, i) {
            final url = ImageHelper.toAbsoluteUrl(ordered[i].imageUrl);
            return Image.network(
              url ?? '',
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: Colors.grey[200],
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              },
              errorBuilder: (ctx, _, __) => Container(
                color: Colors.grey[300],
                child: const Center(child: Icon(Icons.broken_image_outlined, size: 60, color: Colors.grey)),
              ),
            );
          },
        ),
        _headerGradient(),
        if (ordered.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(ordered.length, (i) {
                final active = i == _photoIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? Colors.white : Colors.white54,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _headerGradient() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.4), Colors.transparent, Colors.transparent],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _photoController.dispose();
    super.dispose();
  }

  // Виджет Карточки для Блоков (Стиль Домклика)
  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))]),
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

  Widget _buildScoreRequestButton() {
    return GestureDetector(
      onTap: _loadScore,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: primaryOrange.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.analytics_rounded, color: primaryOrange, size: 18),
            const SizedBox(width: 10),
            const Text(
              'Оценить под мой проект поиска',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildCompetitorsButton(ScoredProperty scored) {
    final direct = scored.directCompetitorNames.length;
    final indirect = scored.indirectCompetitorNames.length;

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _CompetitorsSheet(
          directNames: scored.directCompetitorNames,
          indirectNames: scored.indirectCompetitorNames,
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: primaryOrange.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.storefront_rounded, color: primaryOrange, size: 18),
            const SizedBox(width: 10),
            const Text(
              'Конкуренты рядом',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'прям. $direct',
                style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'косв. $indirect',
                style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAiExplainButton() {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AiExplainSheet(
          propertyId: widget.property.id,
          profileId: widget.profileId,
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A2E), Color(0xFF2D2B55)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFFFF8C00), size: 18),
            SizedBox(width: 10),
            Text(
              'Объяснить оценку',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.2,
              ),
            ),
            Spacer(),
            Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfrastructureSection() {
    return FutureBuilder<List<PoiDto>>(
      future: _poiFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return const Text('Данные об инфраструктуре недоступны', style: TextStyle(color: Colors.grey));
        }

        final pois = snapshot.data!;
        
        return Column(
          children: pois.take(5).map((poi) {
            IconData icon = Icons.place;
            Color iconColor = Colors.grey;
            if (poi.category == 'metro') { icon = Icons.subway; iconColor = Colors.red; }
            else if (poi.category == 'cafe') { icon = Icons.local_cafe; iconColor = Colors.brown; }
            else if (poi.category == 'university') { icon = Icons.school; iconColor = Colors.blue; }
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(poi.name, style: const TextStyle(fontSize: 15)),
                  ),
                  Text(
                    '${poi.distanceMeters.toInt()} м',
                    style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Шторка со списком конкурентов (прямые и косвенные)
// ═══════════════════════════════════════════════════════════════════════════

class _CompetitorsSheet extends StatelessWidget {
  final List<String> directNames;
  final List<String> indirectNames;

  const _CompetitorsSheet({
    required this.directNames,
    required this.indirectNames,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.storefront_rounded, color: Color(0xFFFF8C00), size: 22),
                  const SizedBox(width: 10),
                  const Text(
                    'Конкуренты в радиусе поиска',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding + 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildGroup(
                      title: 'Прямые конкуренты',
                      count: directNames.length,
                      color: const Color(0xFFEF4444),
                      names: directNames,
                      emptyText: 'Прямых конкурентов рядом не найдено',
                    ),
                    const SizedBox(height: 20),
                    _buildGroup(
                      title: 'Косвенные конкуренты',
                      count: indirectNames.length,
                      color: const Color(0xFFF59E0B),
                      names: indirectNames,
                      emptyText: 'Косвенных конкурентов рядом не найдено',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroup({
    required String title,
    required int count,
    required Color color,
    required List<String> names,
    required String emptyText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (names.isEmpty)
          Text(emptyText, style: const TextStyle(color: Colors.grey, fontSize: 13))
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: names.map((name) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.location_on_outlined, size: 16, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name.isNotEmpty ? name : 'Без названия',
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  AI BottomSheet — загружает и показывает объяснение оценки
// ═══════════════════════════════════════════════════════════════════════════

class _AiExplainSheet extends StatefulWidget {
  final int propertyId;
  final int? profileId;

  const _AiExplainSheet({required this.propertyId, this.profileId});

  @override
  State<_AiExplainSheet> createState() => _AiExplainSheetState();
}

class _AiExplainSheetState extends State<_AiExplainSheet> {
  String? _explanation;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final result = await PropertyService()
        .explainScore(widget.propertyId, profileId: widget.profileId);
    if (!mounted) return;
    setState(() {
      _explanation = result;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ручка
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 4),

            // Шапка с градиентом
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A2E), Color(0xFF2D2B55)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF8C00).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Color(0xFFFF8C00), size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Анализ помещения',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        'Объяснение оценки по данным алгоритма',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Тело — скроллируемое, не переполняет экран
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding + 28),
                child: _isLoading
                    ? Column(
                        children: [
                          const SizedBox(height: 16),
                          const _TypingIndicator(),
                          const SizedBox(height: 16),
                        ],
                      )

                    : _explanation != null
                        ? Text(
                            _explanation!,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.65,
                              color: Colors.black87,
                            ),
                          )
                        : const Row(
                            children: [
                              Icon(Icons.wifi_off_rounded, color: Colors.grey, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'AI-анализ временно недоступен',
                                style: TextStyle(color: Colors.grey, fontSize: 14),
                              ),
                            ],
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Анимация "ПЕЧАТАЕТ..." с прыгающими точками
// ═══════════════════════════════════════════════════════════════════════════

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> {
  int _step = 0;
  late final Timer _timer;

  static const _dots = ['', '.', '..', '...'];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (mounted) setState(() => _step = (_step + 1) % _dots.length);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      'ПЕЧАТАЕТ${_dots[_step]}',
      style: const TextStyle(
        color: Color(0xFFFF8C00),
        fontSize: 14,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      ),
    );
  }
}