import 'package:flutter/material.dart';
import '../../../domain/property.dart';
import '../../../services/property_service.dart';
import 'analytics_screen.dart';

class MyPropertiesScreen extends StatefulWidget {
  const MyPropertiesScreen({super.key});

  @override
  State<MyPropertiesScreen> createState() => MyPropertiesScreenState();
}

class MyPropertiesScreenState extends State<MyPropertiesScreen> {
  final PropertyService _propertyService = PropertyService();
  late Future<List<Property>> _propertiesFuture;
  final Color _primaryOrange = const Color(0xFFFF8C00);

  // Фильтры
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  // null = все; иначе 'PUBLISHED' / 'ARCHIVED'
  String? _statusFilter;
  // null = все; иначе 'OFFICE' / 'RETAIL' / 'WAREHOUSE' / 'PSN' / 'CATERING'
  String? _typeFilter;

  // Лейблы для чипов "Тип помещения" — ключ = бэкендовый enum
  static const Map<String, String> _typeLabels = {
    'OFFICE': 'Офис',
    'RETAIL': 'Стрит-ритейл',
    'WAREHOUSE': 'Склад',
    'PSN': 'ПСН',
    'CATERING': 'Общепит',
  };

  @override
  void initState() {
    super.initState();
    loadProperties();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Загрузка списка объектов (публичный — вызывается извне после добавления)
  Future<void> loadProperties() async {
    final future = _propertyService.getMyProperties();
    setState(() {
      _propertiesFuture = future;
    });
    await future;
  }

  bool get _hasActiveFilters =>
      _searchQuery.isNotEmpty || _statusFilter != null || _typeFilter != null;

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _statusFilter = null;
      _typeFilter = null;
    });
  }

  List<Property> _applyFilters(List<Property> source) {
    return source.where((p) {
      if (_statusFilter != null) {
        // На бэке "не архив" может быть как 'PUBLISHED', так и null —
        // считаем активным всё, что НЕ ARCHIVED.
        final isArchived = (p.status ?? '').toUpperCase() == 'ARCHIVED';
        if (_statusFilter == 'ARCHIVED' && !isArchived) return false;
        if (_statusFilter == 'PUBLISHED' && isArchived) return false;
      }
      if (_typeFilter != null && p.propertyType != _typeFilter) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery;
        final hay = '${p.title} ${p.address}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  // Метод для удаления с диалогом подтверждения
  Future<void> _deleteProperty(int propertyId, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Удаление объекта', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Вы уверены, что хотите удалить "$title"?\n\nОбъект будет скрыт, но старые заявки на него останутся доступны.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Удалить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Показываем индикатор загрузки снизу
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Удаляем...'), duration: Duration(seconds: 1)),
    );

    final success = await _propertyService.deleteProperty(propertyId);

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Объект успешно удален'), backgroundColor: Colors.green),
      );
      loadProperties(); // Перезагружаем список
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка при удалении'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Мои объекты', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_hasActiveFilters)
            IconButton(
              tooltip: 'Сбросить фильтры',
              icon: Icon(Icons.filter_alt_off_outlined, color: _primaryOrange),
              onPressed: _resetFilters,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildFiltersBar(),
          Expanded(
            child: FutureBuilder<List<Property>>(
              future: _propertiesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.black));
                } else if (snapshot.hasError) {
                  return const Center(child: Text('Ошибка при загрузке данных'));
                }

                final all = snapshot.data ?? const <Property>[];
                final filtered = _applyFilters(all);

                if (filtered.isEmpty) {
                  return RefreshIndicator(
                    color: _primaryOrange,
                    onRefresh: loadProperties,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.65,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  all.isEmpty
                                      ? Icons.business_outlined
                                      : Icons.search_off_rounded,
                                  size: 80,
                                  color: Colors.grey[300],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  all.isEmpty
                                      ? 'У вас пока нет добавленных объектов'
                                      : 'По заданным фильтрам ничего не найдено',
                                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                                  textAlign: TextAlign.center,
                                ),
                                if (all.isNotEmpty && _hasActiveFilters) ...[
                                  const SizedBox(height: 12),
                                  TextButton.icon(
                                    onPressed: _resetFilters,
                                    icon: Icon(Icons.filter_alt_off_outlined, color: _primaryOrange),
                                    label: Text('Сбросить фильтры', style: TextStyle(color: _primaryOrange)),
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

                // Кнопка "Общая аналитика" показывается только если есть хотя бы
                // один НЕ архивный объект (общая аналитика считается именно по ним).
                final hasNonArchived = all.any(
                  (p) => (p.status ?? '').toUpperCase() != 'ARCHIVED',
                );

                return RefreshIndicator(
                  color: _primaryOrange,
                  onRefresh: loadProperties,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 120),
                    itemCount: filtered.length + 1, // +1 — футер с кнопкой общей аналитики
                    itemBuilder: (context, index) {
                      // Футер
                      if (index == filtered.length) {
                        if (!hasNonArchived) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _buildOverallAnalyticsButton(),
                        );
                      }

                      final property = filtered[index];
                      final isArchived = (property.status ?? '').toUpperCase() == 'ARCHIVED';
                      final isLast = index == filtered.length - 1;

                      return Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                        child: _buildPropertyCard(property, isArchived),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openPropertyAnalytics(Property property) {
    final isArchived = (property.status ?? '').toUpperCase() == 'ARCHIVED';
    if (isArchived) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Объект в архиве — аналитика недоступна')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnalyticsScreen(
          propertyId: property.id,
          propertyTitle: property.title,
        ),
      ),
    );
  }

  void _openOverallAnalytics() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AnalyticsScreen(),
      ),
    );
  }

  Widget _buildOverallAnalyticsButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _openOverallAnalytics,
        icon: const Icon(Icons.bar_chart_rounded, color: Colors.white),
        label: const Text(
          'Общая аналитика по всем объектам',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryOrange,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
        ),
      ),
    );
  }

  Widget _buildPropertyCard(Property property, bool isArchived) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isArchived ? null : () => _openPropertyAnalytics(property),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: _primaryOrange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.storefront, color: _primaryOrange, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            property.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isArchived) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Архив',
                              style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      property.address,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '${property.pricePerMonth} ₽/мес',
                          style: TextStyle(
                              color: _primaryOrange,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                        const Spacer(),
                        if (!isArchived)
                          Row(
                            children: [
                              Icon(Icons.bar_chart_rounded,
                                  size: 16, color: Colors.grey[500]),
                              const SizedBox(width: 4),
                              Text(
                                'Аналитика',
                                style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 2),
                              Icon(Icons.chevron_right,
                                  size: 16, color: Colors.grey[500]),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _deleteProperty(property.id, property.title),
                tooltip: 'Удалить объект',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFiltersBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Поиск
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Поиск по названию или адресу',
                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF1F3F5),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Статус
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildFilterChip(
                  label: 'Все',
                  selected: _statusFilter == null,
                  onTap: () => setState(() => _statusFilter = null),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Активные',
                  selected: _statusFilter == 'PUBLISHED',
                  onTap: () => setState(() => _statusFilter = 'PUBLISHED'),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Архив',
                  selected: _statusFilter == 'ARCHIVED',
                  onTap: () => setState(() => _statusFilter = 'ARCHIVED'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Тип помещения
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildFilterChip(
                  label: 'Все типы',
                  selected: _typeFilter == null,
                  onTap: () => setState(() => _typeFilter = null),
                ),
                for (final entry in _typeLabels.entries) ...[
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: entry.value,
                    selected: _typeFilter == entry.key,
                    onTap: () => setState(() => _typeFilter = entry.key),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _primaryOrange : const Color(0xFFF1F3F5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _primaryOrange : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
