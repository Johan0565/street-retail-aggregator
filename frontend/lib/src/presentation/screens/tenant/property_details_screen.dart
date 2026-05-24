import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../domain/property.dart';
import '../../../domain/search_profile.dart';
import '../../../services/application_service.dart';
import '../../../services/favorite_service.dart';
import '../../../services/analytics_service.dart';
import '../../../services/image_helper.dart';
import '../../../services/property_service.dart';

/// Результат, который PropertyDetailsScreen возвращает MapScreen-у, когда
/// пользователь тапнул конкретного соседа в шторке «Конкуренты»/«Синергия».
/// MapScreen анимирует камеру к этим координатам.
class PropertyDetailsFocusResult {
  final double latitude;
  final double longitude;
  const PropertyDetailsFocusResult({required this.latitude, required this.longitude});
}

class PropertyDetailsScreen extends StatefulWidget {
  final Property property;
  final bool isLandlordMode;
  final ScoredProperty? scoredProperty; // необязательный результат скоринга
  /// ID проекта поиска, под который строится скоринг и AI-отчёт. Если не
  /// задан — бэкенд использует первый активный проект арендатора.
  final int? profileId;
  /// Список желаемых соседей-категорий, выбранных пользователем при создании
  /// проекта поиска. Показываются в шторке «Синергия», даже если рядом
  /// никого из них не нашлось.
  final List<String> desiredNeighborNames;

  const PropertyDetailsScreen({
    super.key,
    required this.property,
    this.isLandlordMode = false,
    this.scoredProperty,
    this.profileId,
    this.desiredNeighborNames = const [],
  });

  @override
  State<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends State<PropertyDetailsScreen> {
  final Color primaryOrange = const Color(0xFFFF8C00);

  bool _isFavorite = false;
  bool _isLoadingFavorite = false;
  bool _isCheckingInitialState = true;

  final PageController _photoController = PageController();
  int _photoIndex = 0;

  // Скоринг, подгружаемый с бэкенда (когда scoredProperty не передан извне)
  ScoredProperty? _loadedScore;
  bool _isLoadingScore = false;

  // Полная версия объекта, дозагруженная по id. Список картинок в карусели
  // берём отсюда: список /api/properties может вернуть объект без images
  // из-за обрезания/lazy-инициализации на бэке, а карточка должна показывать
  // все фото и галерею.
  Property? _fullProperty;

  List<PropertyImage> get _carouselImages =>
      _fullProperty?.images ?? widget.property.images;

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
    _fetchFullProperty();
  }

  Future<void> _fetchFullProperty() async {
    final full = await PropertyService().getPropertyById(widget.property.id);
    if (!mounted || full == null) return;
    setState(() => _fullProperty = full);
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

  /// Закрывает модальную шторку и сам экран деталей, возвращая координаты
  /// выбранного POI наверх — MapScreen анимирует к ним камеру.
  void _focusLocationAndClose(double lat, double lon) {
    final nav = Navigator.of(context);
    // 1) Закрыть шторку (она на верхушке навигатора).
    nav.pop();
    // 2) Закрыть сам экран деталей, передав координаты для фокуса карты.
    nav.pop(PropertyDetailsFocusResult(latitude: lat, longitude: lon));
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
          _scoreBar('Финансовый', scored.financialScore, 20),
          _scoreBar('Технический', scored.technicalScore, 20),
          _scoreBar('Конкуренты', scored.competitorScore, 40),
          _scoreBar('Синергия', scored.synergyScore, 15),
          _scoreBar('Транспорт', scored.transportScore, 5),
          if (scored.breakdown?.transport != null) ...[
            const SizedBox(height: 4),
            Text(
              '5 баллов отведены на доступ к общественному транспорту: '
              '${scored.breakdown!.transport!.reason ?? scored.breakdown!.transport!.typeLabel}.',
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ],
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
      child: _Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Имитация бейджика «N% — match»
            Row(
              children: const [
                _SkeletonBox(width: 18, height: 18, shape: BoxShape.circle),
                SizedBox(width: 8),
                _SkeletonBox(width: 170, height: 14),
              ],
            ),
            const SizedBox(height: 16),
            // 5 строк-полосок повторяют структуру _scoreBar(label, progress, value)
            ...List.generate(5, (i) {
              const labelWidths = [78.0, 86.0, 92.0, 70.0, 80.0];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    _SkeletonBox(width: labelWidths[i], height: 10),
                    const SizedBox(width: 22),
                    const Expanded(child: _SkeletonBox(height: 10)),
                    const SizedBox(width: 8),
                    const _SkeletonBox(width: 30, height: 10),
                  ],
                ),
              );
            }),
          ],
        ),
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
                    if (widget.desiredNeighborNames.isNotEmpty ||
                        (widget.scoredProperty ?? _loadedScore)!.synergyNeighborNames.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _buildSynergyButton((widget.scoredProperty ?? _loadedScore)!),
                    ],
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
                ],
              ),
            ),
          ),
        ],
      ),

      // КНОПКА ЗАЯВКИ СНИЗУ (только для арендатора)
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: !widget.isLandlordMode
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: widget.property.status == 'ARCHIVED'
                      ? null
                      : () => _showApplicationSheet(context, widget.property),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.property.status == 'ARCHIVED'
                        ? Colors.grey
                        : primaryOrange,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 6,
                    shadowColor: Colors.black.withValues(alpha: 0.25),
                  ),
                  child: Text(
                    widget.property.status == 'ARCHIVED'
                        ? 'Недоступно'
                        : 'Оставить заявку',
                    style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildPhotoHeader() {
    final images = _carouselImages;
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
            return CachedNetworkImage(
              imageUrl: url ?? '',
              fit: BoxFit.cover,
              placeholder: (ctx, _) => Container(
                color: Colors.grey[200],
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              errorWidget: (ctx, _, _) => Container(
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
    final directRefs = scored.breakdown?.competitor?.directRefs ?? const <CompetitorRef>[];

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _CompetitorsSheet(
          directNames: scored.directCompetitorNames,
          directRefs: directRefs,
          onLocationTap: _focusLocationAndClose,
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
                '$direct',
                style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSynergyButton(ScoredProperty scored) {
    final selectedCount = widget.desiredNeighborNames.length;
    final foundCount = scored.synergyNeighborNames.length;
    const synergyColor = Color(0xFF22C55E);
    final badgeText = selectedCount > 0 ? '$foundCount / $selectedCount' : '$foundCount';

    final foundRefs = scored.breakdown?.synergy?.refs ?? const <SynergyRef>[];

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _SynergySheet(
          selectedCategories: widget.desiredNeighborNames,
          foundNames: scored.synergyNeighborNames,
          foundRefs: foundRefs,
          onLocationTap: _focusLocationAndClose,
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: synergyColor.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.handshake_rounded, color: synergyColor, size: 18),
            const SizedBox(width: 10),
            const Text(
              'Синергия',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: synergyColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badgeText,
                style: const TextStyle(color: synergyColor, fontWeight: FontWeight.bold, fontSize: 11),
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

}

// ═══════════════════════════════════════════════════════════════════════════
//  Шторка со списком прямых конкурентов
// ═══════════════════════════════════════════════════════════════════════════

class _CompetitorsSheet extends StatelessWidget {
  final List<String> directNames;
  /// Дополнительная инфа с координатами. Если индекс в refs совпадает с
  /// индексом в *Names (бэкенд отдаёт их в одном порядке), элемент списка
  /// становится тапабельным и переводит карту к этому соседу.
  final List<CompetitorRef> directRefs;
  /// Колбэк PropertyDetailsScreen-а: закрывает шторку и экран деталей,
  /// возвращая выбранные координаты на карту.
  final void Function(double lat, double lon) onLocationTap;

  const _CompetitorsSheet({
    required this.directNames,
    required this.directRefs,
    required this.onLocationTap,
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
                      refs: directRefs,
                      emptyText: 'Прямых конкурентов рядом не найдено',
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
    required List<CompetitorRef> refs,
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
            children: List.generate(names.length, (i) {
              final name = names[i];
              // Бэкенд отдаёт names и refs в одном порядке, но подстрахуемся
              // по индексу. Если у ref нет координат — оставляем строку
              // невыпклой и не тапабельной.
              final ref = i < refs.length ? refs[i] : null;
              final lat = ref?.latitude;
              final lon = ref?.longitude;
              final tappable = lat != null && lon != null;
              return _competitorRow(
                name: name,
                color: color,
                impact: ref?.scoreImpact ?? 0,
                onTap: tappable ? () => onLocationTap(lat, lon) : null,
              );
            }),
          ),
      ],
    );
  }

  Widget _competitorRow({
    required String name,
    required Color color,
    required double impact,
    VoidCallback? onTap,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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
          _scoreImpactChip(impact),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey[400]),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: row,
      ),
    );
  }

  /// Чип с дельтой балла: «−1.2» красным для конкурента, «+0.8» зелёным
  /// для соседа, серый «0» если бизнес не повлиял на скор.
  static Widget _scoreImpactChip(double impact) {
    final rounded = (impact * 10).round() / 10.0;
    final isZero = rounded.abs() < 0.05;
    final Color color = isZero
        ? const Color(0xFF94A3B8)
        : (rounded > 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444));
    final String text = isZero
        ? '0'
        : (rounded > 0
            ? '+${rounded.toStringAsFixed(1)}'
            : rounded.toStringAsFixed(1)); // знак минус уже в числе
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Шторка со списком зданий-«синергии» (желаемые соседи)
// ═══════════════════════════════════════════════════════════════════════════

class _SynergySheet extends StatelessWidget {
  /// Категории-соседи, выбранные при создании проекта поиска.
  final List<String> selectedCategories;
  /// Названия зданий/бизнесов из этих категорий, реально найденных в радиусе.
  final List<String> foundNames;
  /// Найденные соседи с координатами — для перехода к ним по тапу.
  final List<SynergyRef> foundRefs;
  /// Закрывает шторку + экран и просит карту сфокусироваться на координатах.
  final void Function(double lat, double lon) onLocationTap;

  const _SynergySheet({
    required this.selectedCategories,
    required this.foundNames,
    required this.foundRefs,
    required this.onLocationTap,
  });

  @override
  Widget build(BuildContext context) {
    const synergyColor = Color(0xFF22C55E);
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
                  const Icon(Icons.handshake_rounded, color: synergyColor, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Синергия',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: synergyColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${foundNames.length} / ${selectedCategories.length}',
                      style: const TextStyle(color: synergyColor, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
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
                    _buildSection(
                      title: 'Выбранные категории при создании проекта',
                      count: selectedCategories.length,
                      items: selectedCategories,
                      emptyText: 'Категории-соседи не выбраны',
                      icon: Icons.check_circle_outline,
                    ),
                    const SizedBox(height: 20),
                    _buildSection(
                      title: 'Найдено рядом',
                      count: foundNames.length,
                      items: foundNames,
                      refs: foundRefs,
                      emptyText: 'Желаемых соседей рядом не найдено',
                      icon: Icons.location_on_outlined,
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

  Widget _buildSection({
    required String title,
    required int count,
    required List<String> items,
    required String emptyText,
    required IconData icon,
    List<SynergyRef> refs = const [],
  }) {
    const synergyColor = Color(0xFF22C55E);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: synergyColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: synergyColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(color: synergyColor, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Text(emptyText, style: const TextStyle(color: Colors.grey, fontSize: 13))
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(items.length, (i) {
              final name = items[i];
              final ref = i < refs.length ? refs[i] : null;
              final lat = ref?.latitude;
              final lon = ref?.longitude;
              final tappable = lat != null && lon != null;
              // У «Выбранные категории при создании проекта» refs пустой —
              // тогда чип не рисуем (это просто список названий категорий).
              final hasImpactInfo = ref != null;
              final row = Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 16, color: synergyColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name.isNotEmpty ? name : 'Без названия',
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                      ),
                    ),
                    if (hasImpactInfo) _CompetitorsSheet._scoreImpactChip(ref.scoreImpact),
                    if (tappable) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey[400]),
                    ],
                  ],
                ),
              );
              if (!tappable) return row;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onLocationTap(lat, lon),
                  child: row,
                ),
              );
            }),
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

  /// Сколько символов из [_explanation] уже «напечатано». Растёт по таймеру.
  int _typedLength = 0;
  Timer? _typingTimer;

  /// Скорость печати: 2 символа каждые 18 мс ≈ 110 знаков/сек. Достаточно
  /// быстро, чтобы не раздражать, но медленно, чтобы воспринималось как «AI печатает».
  static const _typingTickMs = 18;
  static const _typingCharsPerTick = 2;

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
      _typedLength = 0;
    });
    if (result != null && result.isNotEmpty) {
      _startTyping();
    }
  }

  void _startTyping() {
    _typingTimer?.cancel();
    _typingTimer = Timer.periodic(const Duration(milliseconds: _typingTickMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final total = _explanation?.length ?? 0;
      if (_typedLength >= total) {
        timer.cancel();
        return;
      }
      setState(() {
        _typedLength = (_typedLength + _typingCharsPerTick).clamp(0, total);
      });
    });
  }

  /// Тап по тексту во время печати — мгновенно «домотать» до конца.
  void _skipTyping() {
    final total = _explanation?.length ?? 0;
    if (_typedLength >= total) return;
    _typingTimer?.cancel();
    setState(() => _typedLength = total);
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    super.dispose();
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
                    ? _Shimmer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            // «Первый абзац» — 3 строки, последняя короче
                            _SkeletonBox(height: 13),
                            SizedBox(height: 10),
                            _SkeletonBox(height: 13),
                            SizedBox(height: 10),
                            _SkeletonBox(width: 220, height: 13),
                            SizedBox(height: 22),
                            // «Второй абзац» — 3 строки
                            _SkeletonBox(height: 13),
                            SizedBox(height: 10),
                            _SkeletonBox(height: 13),
                            SizedBox(height: 10),
                            _SkeletonBox(width: 180, height: 13),
                            SizedBox(height: 22),
                            // «Вывод» — 2 короткие строки
                            _SkeletonBox(width: 260, height: 13),
                            SizedBox(height: 10),
                            _SkeletonBox(width: 140, height: 13),
                          ],
                        ),
                      )
                    : _explanation != null
                        ? GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _skipTyping,
                            child: _TypewriterText(
                              fullText: _explanation!,
                              typedLength: _typedLength,
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
//  Typewriter — постепенно проявляет [typedLength] символов из [fullText]
//  и рисует мигающий курсор в конце, пока печать не завершена.
// ═══════════════════════════════════════════════════════════════════════════

class _TypewriterText extends StatelessWidget {
  final String fullText;
  final int typedLength;

  const _TypewriterText({required this.fullText, required this.typedLength});

  @override
  Widget build(BuildContext context) {
    final clamped = typedLength.clamp(0, fullText.length);
    final visible = fullText.substring(0, clamped);
    final isDone = clamped >= fullText.length;

    const textStyle = TextStyle(
      fontSize: 15,
      height: 1.65,
      color: Colors.black87,
    );

    return RichText(
      text: TextSpan(
        style: textStyle,
        children: [
          TextSpan(text: visible),
          if (!isDone)
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _BlinkingCursor(),
            ),
        ],
      ),
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        final opacity = _controller.value < 0.5 ? 1.0 : 0.0;
        return Opacity(
          opacity: opacity,
          child: Container(
            margin: const EdgeInsets.only(left: 2),
            width: 2,
            height: 16,
            color: const Color(0xFFFF8C00),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Skeleton — серый «слепок» итогового контента с бегущим shimmer-бликом.
//  Используется вместо CircularProgressIndicator на карточках, чтобы загрузка
//  ощущалась быстрее и не было прыжка макета при появлении данных.
// ═══════════════════════════════════════════════════════════════════════════

class _Shimmer extends StatefulWidget {
  final Widget child;
  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _base = Color(0xFFE5E7EB);
  static const _highlight = Color(0xFFF7F8FA);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        // dx ∈ [-1, 2] — блик уезжает левее левого края и заезжает правее правого,
        // чтобы цикл выглядел бесшовным.
        final dx = _controller.value * 3 - 1;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            colors: const [_base, _highlight, _base],
            stops: const [0.35, 0.5, 0.65],
            begin: Alignment(dx - 1, 0),
            end: Alignment(dx + 1, 0),
          ).createShader(bounds),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final BoxShape shape;

  const _SkeletonBox({
    this.width,
    required this.height,
    this.shape = BoxShape.rectangle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        shape: shape,
        borderRadius:
            shape == BoxShape.rectangle ? BorderRadius.circular(6) : null,
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