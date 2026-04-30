import 'package:flutter/material.dart';

import '../../../domain/search_profile.dart';
import '../../../services/category_service.dart';
import '../../../services/search_profile_service.dart';

/// Экран «Мои проекты поиска» — список проектов + создание нового.
class SearchProfilesScreen extends StatefulWidget {
  const SearchProfilesScreen({super.key});

  @override
  State<SearchProfilesScreen> createState() => _SearchProfilesScreenState();
}

class _SearchProfilesScreenState extends State<SearchProfilesScreen> {
  final SearchProfileService _service = SearchProfileService();
  final Color _primaryOrange = const Color(0xFFFF8C00);

  List<SearchProfile> _profiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() => _isLoading = true);
    final profiles = await _service.getMyProfiles();
    if (mounted) {
      setState(() {
        _profiles = profiles;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteProfile(SearchProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Удалить проект?'),
        content: Text('«${profile.name}» будет удалён навсегда.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final success = await _service.deleteProfile(profile.id);
      if (success) {
        _loadProfiles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Проект удалён'), backgroundColor: Colors.black87),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Проекты поиска',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const CreateSearchProfileScreen()),
          );
          if (result == true) _loadProfiles();
        },
        backgroundColor: Colors.black,
        icon: Icon(Icons.add, color: _primaryOrange),
        label: Text('Новый проект', style: TextStyle(color: _primaryOrange, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _profiles.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadProfiles,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _profiles.length,
                    itemBuilder: (context, index) => _buildProfileCard(_profiles[index]),
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('Нет проектов поиска',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black54)),
          const SizedBox(height: 8),
          const Text('Создайте проект, чтобы алгоритм\nподбирал помещения под ваш бизнес',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const CreateSearchProfileScreen()),
              );
              if (result == true) _loadProfiles();
            },
            icon: const Icon(Icons.add),
            label: const Text('Создать первый проект', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: _primaryOrange,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(SearchProfile profile) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            final result = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => CreateSearchProfileScreen(existingProfile: profile),
              ),
            );
            if (result == true) _loadProfiles();
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _primaryOrange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.manage_search_rounded, color: _primaryOrange, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(profile.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          if (profile.businessCategoryName != null)
                            Text(profile.businessCategoryName!,
                                style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _deleteProfile(profile),
                      tooltip: 'Удалить',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Параметры поиска
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (profile.minBudget != null && profile.maxBudget != null)
                      _buildTag(Icons.payments_outlined,
                          '${_fmt(profile.minBudget!)} – ${_fmt(profile.maxBudget!)} ₽'),
                    if (profile.minArea != null && profile.maxArea != null)
                      _buildTag(Icons.square_foot, '${profile.minArea!.toInt()}–${profile.maxArea!.toInt()} м²'),
                    if (profile.minPowerKw != null)
                      _buildTag(Icons.bolt, 'от ${profile.minPowerKw} кВт'),
                    if (profile.minCeilingHeight != null)
                      _buildTag(Icons.height, '≥ ${profile.minCeilingHeight} м'),
                    if (profile.requiresWater == true) _buildTag(Icons.water_drop, 'Вода'),
                    if (profile.requiresVentilation == true) _buildTag(Icons.air, 'Вытяжка'),
                    if (profile.requiresSeparateEntrance == true) _buildTag(Icons.door_front_door, 'Отд. вход'),
                    if (profile.requiresWc == true) _buildTag(Icons.wc, 'Санузел'),
                    if (profile.requiresParking == true) _buildTag(Icons.local_parking, 'Парковка'),
                    if (profile.requiresLoadingZone == true) _buildTag(Icons.local_shipping, 'Разгрузка'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTag(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.black54),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black87)),
        ],
      ),
    );
  }

  String _fmt(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}М';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}К';
    return value.toStringAsFixed(0);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ЭКРАН СОЗДАНИЯ / РЕДАКТИРОВАНИЯ ПРОФИЛЯ ПОИСКА
// ═══════════════════════════════════════════════════════════════════════════

class CreateSearchProfileScreen extends StatefulWidget {
  final SearchProfile? existingProfile;

  const CreateSearchProfileScreen({super.key, this.existingProfile});

  @override
  State<CreateSearchProfileScreen> createState() => _CreateSearchProfileScreenState();
}

class _CreateSearchProfileScreenState extends State<CreateSearchProfileScreen> {
  final SearchProfileService _service = SearchProfileService();
  final CategoryService _categoryService = CategoryService();
  final Color _primaryOrange = const Color(0xFFFF8C00);

  final _nameController = TextEditingController();
  final _minAreaController = TextEditingController();
  final _maxAreaController = TextEditingController();
  final _minBudgetController = TextEditingController();
  final _maxBudgetController = TextEditingController();
  final _minPowerController = TextEditingController();
  final _minCeilingController = TextEditingController();

  int _currentStep = 0;
  bool _isSaving = false;

  // Технические критерии
  bool _requiresWater = false;
  bool _requiresVentilation = false;
  bool _requiresSeparateEntrance = false;
  bool _requiresWc = false;
  bool _requiresParking = false;
  bool _requiresLoadingZone = false;

  // Категория бизнеса
  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;
  String? _selectedCategoryName;

  bool get _isEditing => widget.existingProfile != null;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    if (_isEditing) _fillFromExisting();
  }

  void _fillFromExisting() {
    final p = widget.existingProfile!;
    _nameController.text = p.name;
    _selectedCategoryId = p.businessCategoryId;
    _selectedCategoryName = p.businessCategoryName;
    if (p.minArea != null) _minAreaController.text = p.minArea!.toInt().toString();
    if (p.maxArea != null) _maxAreaController.text = p.maxArea!.toInt().toString();
    if (p.minBudget != null) _minBudgetController.text = p.minBudget!.toInt().toString();
    if (p.maxBudget != null) _maxBudgetController.text = p.maxBudget!.toInt().toString();
    if (p.minPowerKw != null) _minPowerController.text = p.minPowerKw.toString();
    if (p.minCeilingHeight != null) _minCeilingController.text = p.minCeilingHeight!.toString();
    _requiresWater = p.requiresWater ?? false;
    _requiresVentilation = p.requiresVentilation ?? false;
    _requiresSeparateEntrance = p.requiresSeparateEntrance ?? false;
    _requiresWc = p.requiresWc ?? false;
    _requiresParking = p.requiresParking ?? false;
    _requiresLoadingZone = p.requiresLoadingZone ?? false;
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await _categoryService.getAllCategories();
      if (mounted) setState(() => _categories = cats);
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название проекта'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    final data = <String, dynamic>{
      'name': _nameController.text.trim(),
      if (_selectedCategoryId != null) 'businessCategoryId': _selectedCategoryId,
      if (_minAreaController.text.isNotEmpty) 'minArea': double.tryParse(_minAreaController.text),
      if (_maxAreaController.text.isNotEmpty) 'maxArea': double.tryParse(_maxAreaController.text),
      if (_minBudgetController.text.isNotEmpty) 'minBudget': double.tryParse(_minBudgetController.text),
      if (_maxBudgetController.text.isNotEmpty) 'maxBudget': double.tryParse(_maxBudgetController.text),
      if (_minPowerController.text.isNotEmpty) 'minPowerKw': int.tryParse(_minPowerController.text),
      if (_minCeilingController.text.isNotEmpty) 'minCeilingHeight': double.tryParse(_minCeilingController.text),
      'requiresWater': _requiresWater,
      'requiresVentilation': _requiresVentilation,
      'requiresSeparateEntrance': _requiresSeparateEntrance,
      'requiresWc': _requiresWc,
      'requiresParking': _requiresParking,
      'requiresLoadingZone': _requiresLoadingZone,
    };

    SearchProfile? result;
    if (_isEditing) {
      result = await _service.updateProfile(widget.existingProfile!.id, data);
    } else {
      result = await _service.createProfile(data);
    }

    setState(() => _isSaving = false);

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Проект обновлён' : 'Проект создан!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка сохранения'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _isEditing ? 'Редактировать проект' : 'Новый проект поиска',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < 2) {
            setState(() => _currentStep++);
          } else {
            _save();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) setState(() => _currentStep--);
        },
        controlsBuilder: (context, details) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: [
              ElevatedButton(
                onPressed: _isSaving ? null : details.onStepContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving && _currentStep == 2
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        _currentStep == 2 ? (_isEditing ? 'Сохранить' : 'Создать') : 'Далее',
                        style: TextStyle(color: _primaryOrange, fontWeight: FontWeight.bold),
                      ),
              ),
              if (_currentStep > 0) ...[
                const SizedBox(width: 12),
                TextButton(
                  onPressed: details.onStepCancel,
                  child: const Text('Назад', style: TextStyle(color: Colors.black54)),
                ),
              ],
            ],
          ),
        ),
        steps: [
          // ── Шаг 1: Основное ─────────────────────────────────────────────
          Step(
            title: const Text('Основное', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Название и тип бизнеса'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: Column(
              children: [
                _buildTextField(_nameController, 'Название проекта', 'Например: Открыть кофейню'),
                const SizedBox(height: 16),
                // Выбор категории
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: _selectedCategoryId,
                      hint: const Text('Выберите категорию бизнеса', style: TextStyle(color: Colors.black38)),
                      items: _categories.map((cat) {
                        return DropdownMenuItem<int>(
                          value: cat['id'] as int,
                          child: Text(cat['name'] as String),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          final cat = _categories.firstWhere((c) => c['id'] == val);
                          setState(() {
                            _selectedCategoryId = val;
                            _selectedCategoryName = cat['name'] as String;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Шаг 2: Финансы ──────────────────────────────────────────────
          Step(
            title: const Text('Финансы', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Площадь и бюджет'),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            content: Column(
              children: [
                Row(children: [
                  Expanded(child: _buildTextField(_minBudgetController, 'Бюджет от, ₽', '50000', isNumber: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTextField(_maxBudgetController, 'Бюджет до, ₽', '200000', isNumber: true)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _buildTextField(_minAreaController, 'Площадь от, м²', '30', isNumber: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTextField(_maxAreaController, 'Площадь до, м²', '150', isNumber: true)),
                ]),
              ],
            ),
          ),
          // ── Шаг 3: Технические ──────────────────────────────────────────
          Step(
            title: const Text('Технические', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Требования к помещению'),
            isActive: _currentStep >= 2,
            state: StepState.indexed,
            content: Column(
              children: [
                Row(children: [
                  Expanded(child: _buildTextField(_minPowerController, 'Мин. мощность, кВт', '15', isNumber: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTextField(_minCeilingController, 'Мин. высота потолков, м', '2.7', isNumber: true)),
                ]),
                const SizedBox(height: 8),
                _buildSwitch('Нужна мокрая точка (вода)', _requiresWater, (v) => setState(() => _requiresWater = v)),
                _buildSwitch('Нужна вытяжка / вентиляция', _requiresVentilation, (v) => setState(() => _requiresVentilation = v)),
                _buildSwitch('Нужен отдельный вход', _requiresSeparateEntrance, (v) => setState(() => _requiresSeparateEntrance = v)),
                _buildSwitch('Нужен санузел в помещении', _requiresWc, (v) => setState(() => _requiresWc = v)),
                _buildSwitch('Нужна парковка рядом', _requiresParking, (v) => setState(() => _requiresParking = v)),
                _buildSwitch('Нужна зона разгрузки/погрузки', _requiresLoadingZone, (v) => setState(() => _requiresLoadingZone = v)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, String hint,
      {bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _primaryOrange, width: 2),
        ),
      ),
    );
  }

  Widget _buildSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        value: value,
        activeColor: _primaryOrange,
        onChanged: onChanged,
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _minAreaController.dispose();
    _maxAreaController.dispose();
    _minBudgetController.dispose();
    _maxBudgetController.dispose();
    _minPowerController.dispose();
    _minCeilingController.dispose();
    super.dispose();
  }
}
