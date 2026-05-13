import 'dart:io';

import 'package:flutter/material.dart';
import '../../../services/image_helper.dart';
import '../../../services/property_service.dart';
import 'map_picker_screen.dart';

class AddPropertyScreen extends StatefulWidget {
  const AddPropertyScreen({super.key});

  @override
  State<AddPropertyScreen> createState() => _AddPropertyScreenState();
}

class _AddPropertyScreenState extends State<AddPropertyScreen> {
  int _currentStep = 0;
  // 5 шагов: базовая, финансы, технические, контакты, фото
  final _formKeys = [
    GlobalKey<FormState>(),
    GlobalKey<FormState>(),
    GlobalKey<FormState>(),
    GlobalKey<FormState>(),
    GlobalKey<FormState>(),
  ];

  // Фотографии помещения (выбранные до отправки)
  final List<File> _photos = [];
  int _mainPhotoIndex = 0;

  final PropertyService _propertyService = PropertyService();
  final Color _primaryOrange = const Color(0xFFFF8C00);

  // Контроллеры полей
  final _titleController = TextEditingController();
  final _addressController = TextEditingController();
  final _areaController = TextEditingController();
  final _priceController = TextEditingController();
  final _depositController = TextEditingController();
  final _powerController = TextEditingController();
  final _ceilingHeightController = TextEditingController();
  final _descController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();

  // --- НОВЫЙ КОНТРОЛЛЕР ---
  final _cadastralController = TextEditingController();

  // Состояния (Выпадающие списки и переключатели)
  String? _selectedPropertyType;
  String? _selectedDealType;
  String? _selectedRepairState;
  String? _selectedLayout;

  // --- НОВЫЕ СОСТОЯНИЯ ---
  String? _selectedAccessType;
  String? _selectedHeatingType;
  String? _selectedFurnitureState;

  bool _taxIncluded = false;
  bool _utilityIncluded = false;
  bool _hasWater = false;
  bool _hasVentilation = false;
  bool _hasSeparateEntrance = false;
  bool _hasWc = false;
  bool _hasParking = false;
  bool _hasLoadingZone = false;

  // --- НОВЫЙ ПЕРЕКЛЮЧАТЕЛЬ ---
  bool _isOccupied = false;

  double? _selectedLat;
  double? _selectedLon;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose(); _addressController.dispose(); _areaController.dispose();
    _priceController.dispose(); _depositController.dispose(); _powerController.dispose();
    _ceilingHeightController.dispose();
    _descController.dispose(); _contactNameController.dispose(); _contactPhoneController.dispose();
    _cadastralController.dispose(); // Не забываем очищать
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_selectedLat == null || _selectedLon == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Укажите точку на карте! (Шаг 1)'), backgroundColor: Colors.red));
      setState(() => _currentStep = 0);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final propertyId = await _propertyService.createProperty(
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        address: _addressController.text.trim(),
        latitude: _selectedLat!,
        longitude: _selectedLon!,
        areaSqm: double.parse(_areaController.text.trim()),
        pricePerMonth: double.parse(_priceController.text.trim()),
        propertyType: _selectedPropertyType!,
        dealType: _selectedDealType!,
        taxIncluded: _taxIncluded,
        utilityIncluded: _utilityIncluded,
        depositMonths: int.tryParse(_depositController.text.trim()) ?? 1,
        powerKw: int.tryParse(_powerController.text.trim()) ?? 0,
        ceilingHeight: double.tryParse(_ceilingHeightController.text.trim().replaceAll(',', '.')),
        hasWater: _hasWater,
        hasVentilation: _hasVentilation,
        hasSeparateEntrance: _hasSeparateEntrance,
        hasWc: _hasWc,
        hasParking: _hasParking,
        hasLoadingZone: _hasLoadingZone,
        repairState: _selectedRepairState,
        layout: _selectedLayout,
        contactName: _contactNameController.text.trim(),
        contactPhone: _contactPhoneController.text.trim(),
        cadastralNumber: _cadastralController.text.trim().isEmpty ? null : _cadastralController.text.trim(),
        accessType: _selectedAccessType,
        heatingType: _selectedHeatingType,
        furnitureState: _selectedFurnitureState,
        isOccupied: _isOccupied,
      );

      if (propertyId == null) {
        throw Exception('Ошибка создания объекта');
      }

      // Грузим фотографии. Главное фото первым — бэк назначит isMain первой
      // в пустом списке.
      bool photosOk = true;
      if (_photos.isNotEmpty) {
        final ordered = <File>[
          _photos[_mainPhotoIndex],
          ..._photos.asMap().entries.where((e) => e.key != _mainPhotoIndex).map((e) => e.value),
        ];
        photosOk = await _propertyService.uploadPropertyImages(propertyId, ordered);
      }

      if (!mounted) return;
      Navigator.pop(context, true); // true — сигнал родителю, что нужно обновить список
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(photosOk
            ? 'Помещение опубликовано!'
            : 'Объявление создано, но фото не загрузились — добавьте позже'),
        backgroundColor: photosOk ? Colors.green : Colors.orange,
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка публикации. Проверьте данные.'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _addPhotos() async {
    final remaining = 10 - _photos.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Максимум 10 фотографий')),
      );
      return;
    }
    final picked = await ImageHelper.pickImages(context, allowMultiple: true);
    if (picked.isEmpty) return;
    setState(() {
      _photos.addAll(picked.take(remaining));
    });
  }

  void _removePhoto(int index) {
    setState(() {
      _photos.removeAt(index);
      if (_mainPhotoIndex >= _photos.length) {
        _mainPhotoIndex = _photos.isEmpty ? 0 : _photos.length - 1;
      } else if (_mainPhotoIndex == index && _photos.isNotEmpty) {
        _mainPhotoIndex = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Добавить помещение', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: Theme(
          data: ThemeData(colorScheme: ColorScheme.light(primary: _primaryOrange)),
          child: Stepper(
            type: StepperType.vertical,
            currentStep: _currentStep,
            onStepTapped: (step) => setState(() => _currentStep = step),
            onStepContinue: () {
              if (_formKeys[_currentStep].currentState!.validate()) {
                if (_currentStep < 4) {
                  setState(() => _currentStep += 1);
                } else {
                  _submitForm();
                }
              }
            },
            onStepCancel: () {
              if (_currentStep > 0) setState(() => _currentStep -= 1);
            },
            controlsBuilder: (context, details) {
              return Padding(
                padding: const EdgeInsets.only(top: 24.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : details.onStepContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSubmitting && _currentStep == 4
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text(_currentStep == 4 ? 'Опубликовать' : 'Далее', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    if (_currentStep > 0) ...[
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: _isSubmitting ? null : details.onStepCancel,
                        child: const Text('Назад', style: TextStyle(color: Colors.grey)),
                      ),
                    ]
                  ],
                ),
              );
            },
            steps: [
              // ШАГ 1: БАЗОВАЯ ИНФО
              Step(
                title: const Text('Базовая информация', style: TextStyle(fontWeight: FontWeight.bold)),
                isActive: _currentStep >= 0,
                state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                content: Form(
                  key: _formKeys[0],
                  child: Column(
                    children: [
                      _buildTextField(controller: _titleController, label: 'Название объявления', icon: Icons.title),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildDropdown(label: 'Тип', value: _selectedPropertyType, items: {'Офис':'OFFICE', 'Стрит-ритейл':'RETAIL', 'Склад':'WAREHOUSE', 'ПСН':'PSN', 'Общепит':'CATERING'}, onChanged: (v) => setState(() => _selectedPropertyType = v))),
                          const SizedBox(width: 16),
                          Expanded(child: _buildDropdown(label: 'Сделка', value: _selectedDealType, items: {'Прямая':'DIRECT_LEASE', 'Субаренда':'SUBLEASE'}, onChanged: (v) => setState(() => _selectedDealType = v))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(controller: _areaController, label: 'Общая площадь (м²)', icon: Icons.square_foot, isNumber: true),
                      const SizedBox(height: 16),
                      // --- НОВОЕ ПОЛЕ (Необязательное) ---
                      _buildTextField(controller: _cadastralController, label: 'Кадастровый номер (необяз.)', icon: Icons.numbers, isRequired: false),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildTextField(controller: _addressController, label: 'Адрес', icon: Icons.location_on_outlined)),
                          const SizedBox(width: 12),
                          Container(
                            height: 60, width: 60,
                            decoration: BoxDecoration(
                              color: _selectedLat != null ? Colors.green.withOpacity(0.1) : _primaryOrange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _selectedLat != null ? Colors.green : _primaryOrange),
                            ),
                            child: IconButton(
                              icon: Icon(_selectedLat != null ? Icons.check : Icons.map_outlined, color: _selectedLat != null ? Colors.green : _primaryOrange, size: 30),
                              onPressed: () async {
                                final result = await Navigator.push<Map<String, dynamic>>(context, MaterialPageRoute(builder: (context) => const MapPickerScreen()));
                                if (result != null) {
                                  setState(() {
                                    _selectedLat = result['latitude'];
                                    _selectedLon = result['longitude'];
                                  });
                                  final resolvedAddress = result['address'] as String?;
                                  if (resolvedAddress != null && resolvedAddress.trim().isNotEmpty) {
                                    // Подставляем адрес, если поле пустое или пользователь ещё ничего не вводил.
                                    // Если поле уже заполнено вручную — не затираем.
                                    if (_addressController.text.trim().isEmpty) {
                                      _addressController.text = resolvedAddress;
                                    } else {
                                      if (!context.mounted) return;
                                      // Спрашиваем, заменить ли уже введённый адрес
                                      final replace = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          title: const Text('Заменить адрес?'),
                                          content: Text('По метке определён адрес:\n\n$resolvedAddress\n\nЗаменить введённый вами?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx, false),
                                              child: const Text('Оставить мой', style: TextStyle(color: Colors.black54)),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx, true),
                                              child: Text('Заменить', style: TextStyle(color: _primaryOrange, fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (replace == true) {
                                        _addressController.text = resolvedAddress;
                                      }
                                    }
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ШАГ 2: ФИНАНСЫ
              Step(
                title: const Text('Финансовые условия', style: TextStyle(fontWeight: FontWeight.bold)),
                isActive: _currentStep >= 1,
                state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                content: Form(
                  key: _formKeys[1],
                  child: Column(
                    children: [
                      _buildTextField(controller: _priceController, label: 'Арендная ставка (₽/мес)', icon: Icons.currency_ruble, isNumber: true),
                      const SizedBox(height: 16),
                      _buildTextField(controller: _depositController, label: 'Депозит (Кол-во месяцев)', icon: Icons.security, isNumber: true),
                      const SizedBox(height: 8),
                      _buildSwitch(title: 'Включает НДС', value: _taxIncluded, icon: Icons.receipt_long, onChanged: (v) => setState(() => _taxIncluded = v)),
                      _buildSwitch(title: 'Коммуналка включена', value: _utilityIncluded, icon: Icons.water_drop_outlined, onChanged: (v) => setState(() => _utilityIncluded = v)),
                    ],
                  ),
                ),
              ),

              // ШАГ 3: ТЕХНИЧЕСКИЕ (Обновлено)
              Step(
                title: const Text('Технические параметры', style: TextStyle(fontWeight: FontWeight.bold)),
                isActive: _currentStep >= 2,
                state: _currentStep > 2 ? StepState.complete : StepState.indexed,
                content: Form(
                  key: _formKeys[2],
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildTextField(controller: _powerController, label: 'Мощность (кВт)', icon: Icons.bolt, isNumber: true)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildTextField(controller: _ceilingHeightController, label: 'Высота потолков (м)', icon: Icons.height, isNumber: true, isRequired: false)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildDropdown(label: 'Ремонт', value: _selectedRepairState, items: {'Под чистовую':'PRE_FINISHING', 'Типовой':'TYPICAL', 'Дизайнерский':'DESIGNER', 'Без ремонта':'SHELL_AND_CORE'}, onChanged: (v) => setState(() => _selectedRepairState = v), isRequired: false)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildDropdown(label: 'Планировка', value: _selectedLayout, items: {'Open Space':'OPEN_SPACE', 'Кабинетная':'CABINET', 'Смешанная':'MIXED'}, onChanged: (v) => setState(() => _selectedLayout = v), isRequired: false)),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // --- НОВЫЕ ПОЛЯ ИЗ ДОМКЛИКА (Необязательные) ---
                      Row(
                        children: [
                          Expanded(child: _buildDropdown(label: 'Отопление', value: _selectedHeatingType, items: {'Центральное':'CENTRAL', 'Автономное':'AUTONOMOUS', 'Нет':'NONE'}, onChanged: (v) => setState(() => _selectedHeatingType = v), isRequired: false)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildDropdown(label: 'Доступ', value: _selectedAccessType, items: {'24/7':'FREE', 'По расписанию':'SCHEDULE', 'Пропускной':'PASS'}, onChanged: (v) => setState(() => _selectedAccessType = v), isRequired: false)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildDropdown(label: 'Состояние (мебель)', value: _selectedFurnitureState, items: {'Пустое':'EMPTY', 'С мебелью':'FURNISHED', 'Готовый бизнес':'READY_BUSINESS'}, onChanged: (v) => setState(() => _selectedFurnitureState = v), isRequired: false),

                      const SizedBox(height: 8),
                      _buildSwitch(title: 'Сдано в аренду (ГАБ)', value: _isOccupied, icon: Icons.people, onChanged: (v) => setState(() => _isOccupied = v)),
                      _buildSwitch(title: 'Мокрая точка', value: _hasWater, icon: Icons.water_drop, onChanged: (v) => setState(() => _hasWater = v)),
                      _buildSwitch(title: 'Вытяжка', value: _hasVentilation, icon: Icons.air, onChanged: (v) => setState(() => _hasVentilation = v)),
                      _buildSwitch(title: 'Отдельный вход', value: _hasSeparateEntrance, icon: Icons.door_front_door, onChanged: (v) => setState(() => _hasSeparateEntrance = v)),
                      _buildSwitch(title: 'Санузел в помещении', value: _hasWc, icon: Icons.wc, onChanged: (v) => setState(() => _hasWc = v)),
                      _buildSwitch(title: 'Парковка рядом', value: _hasParking, icon: Icons.local_parking, onChanged: (v) => setState(() => _hasParking = v)),
                      _buildSwitch(title: 'Зона разгрузки/погрузки', value: _hasLoadingZone, icon: Icons.local_shipping, onChanged: (v) => setState(() => _hasLoadingZone = v)),
                    ],
                  ),
                ),
              ),

              // ШАГ 4: КОНТАКТЫ
              Step(
                title: const Text('Детали и Контакты', style: TextStyle(fontWeight: FontWeight.bold)),
                isActive: _currentStep >= 3,
                state: _currentStep > 3 ? StepState.complete : StepState.indexed,
                content: Form(
                  key: _formKeys[3],
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _descController, maxLines: 4,
                        validator: (value) => value!.isEmpty ? 'Обязательное поле' : null,
                        decoration: InputDecoration(labelText: 'Текстовое описание объекта', border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(controller: _contactNameController, label: 'Контактное лицо / Компания', icon: Icons.person_outline),
                      const SizedBox(height: 16),
                      _buildTextField(controller: _contactPhoneController, label: 'Телефон для связи', icon: Icons.phone_outlined, isNumber: true),
                    ],
                  ),
                ),
              ),

              // ШАГ 5: ФОТОГРАФИИ
              Step(
                title: const Text('Фотографии', style: TextStyle(fontWeight: FontWeight.bold)),
                isActive: _currentStep >= 4,
                content: Form(
                  key: _formKeys[4],
                  child: _buildPhotosStep(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotosStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Добавьте до 10 фото. Первое (с меткой «Главное») увидят в ленте.',
          style: TextStyle(color: Colors.grey[700], fontSize: 13),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            ..._photos.asMap().entries.map((entry) {
              final index = entry.key;
              final file = entry.value;
              final isMain = index == _mainPhotoIndex;
              return GestureDetector(
                onTap: () => setState(() => _mainPhotoIndex = index),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(file, fit: BoxFit.cover),
                    ),
                    if (isMain)
                      Positioned(
                        left: 4, top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _primaryOrange,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Главное',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    Positioned(
                      right: 2, top: 2,
                      child: GestureDetector(
                        onTap: () => _removePhoto(index),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (_photos.length < 10)
              GestureDetector(
                onTap: _addPhotos,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
                  ),
                  child: const Center(child: Icon(Icons.add_a_photo_outlined, color: Colors.grey)),
                ),
              ),
          ],
        ),
        if (_photos.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Фото необязательны, но без них объявление выглядит хуже.',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ),
      ],
    );
  }

  // ОБНОВЛЕН: добавлен параметр isRequired
  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon, bool isNumber = false, bool isRequired = true}) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      validator: isRequired ? (value) => (value == null || value.trim().isEmpty) ? 'Обязательное поле' : null : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }

  Widget _buildDropdown({required String label, required String? value, required Map<String, String> items, required Function(String?) onChanged, bool isRequired = true}) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: value,
      validator: isRequired ? (val) => val == null ? 'Укажите' : null : null,
      decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16)),
      items: items.entries.map((e) => DropdownMenuItem(value: e.value, child: Text(e.key, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildSwitch({required String title, required bool value, required IconData icon, required Function(bool) onChanged}) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      secondary: Icon(icon, color: _primaryOrange),
      activeColor: _primaryOrange,
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }
}