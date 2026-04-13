import 'package:flutter/material.dart';
import '../../../services/property_service.dart';
import 'map_picker_screen.dart';

class AddPropertyScreen extends StatefulWidget {
  const AddPropertyScreen({super.key});

  @override
  State<AddPropertyScreen> createState() => _AddPropertyScreenState();
}

class _AddPropertyScreenState extends State<AddPropertyScreen> {
  int _currentStep = 0;
  final _formKeys = [GlobalKey<FormState>(), GlobalKey<FormState>(), GlobalKey<FormState>(), GlobalKey<FormState>()];

  final PropertyService _propertyService = PropertyService();
  final Color _primaryOrange = const Color(0xFFFF8C00);

  // Контроллеры полей
  final _titleController = TextEditingController();
  final _addressController = TextEditingController();
  final _areaController = TextEditingController();
  final _priceController = TextEditingController();
  final _depositController = TextEditingController();
  final _powerController = TextEditingController();
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

  // --- НОВЫЙ ПЕРЕКЛЮЧАТЕЛЬ ---
  bool _isOccupied = false;

  double? _selectedLat;
  double? _selectedLon;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose(); _addressController.dispose(); _areaController.dispose();
    _priceController.dispose(); _depositController.dispose(); _powerController.dispose();
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
      final success = await _propertyService.createProperty(
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
        hasWater: _hasWater,
        hasVentilation: _hasVentilation,
        hasSeparateEntrance: _hasSeparateEntrance,
        repairState: _selectedRepairState,
        layout: _selectedLayout,
        contactName: _contactNameController.text.trim(),
        contactPhone: _contactPhoneController.text.trim(),

        // --- ПЕРЕДАЕМ НОВЫЕ ПОЛЯ В СЕРВИС ---
        cadastralNumber: _cadastralController.text.trim().isEmpty ? null : _cadastralController.text.trim(),
        accessType: _selectedAccessType,
        heatingType: _selectedHeatingType,
        furnitureState: _selectedFurnitureState,
        isOccupied: _isOccupied,
      );

      if (success && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Помещение опубликовано!'), backgroundColor: Colors.green));
      } else {
        throw Exception('Ошибка сервера');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка публикации. Проверьте данные.'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
                if (_currentStep < 3) {
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
                        child: _isSubmitting && _currentStep == 3
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text(_currentStep == 3 ? 'Опубликовать' : 'Далее', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                                if (result != null) setState(() { _selectedLat = result['latitude']; _selectedLon = result['longitude']; });
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
                      _buildTextField(controller: _powerController, label: 'Мощность (кВт)', icon: Icons.bolt, isNumber: true),
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
                    ],
                  ),
                ),
              ),

              // ШАГ 4: КОНТАКТЫ
              Step(
                title: const Text('Детали и Контакты', style: TextStyle(fontWeight: FontWeight.bold)),
                isActive: _currentStep >= 3,
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
            ],
          ),
        ),
      ),
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

  // ОБНОВЛЕН: добавлен параметр isRequired
  Widget _buildDropdown({required String label, required String? value, required Map<String, String> items, required Function(String?) onChanged, bool isRequired = true}) {
    return DropdownButtonFormField<String>(
      value: value,
      validator: isRequired ? (val) => val == null ? 'Укажите' : null : null,
      decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16)),
      items: items.entries.map((e) => DropdownMenuItem(value: e.value, child: Text(e.key, style: const TextStyle(fontSize: 14)))).toList(),
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