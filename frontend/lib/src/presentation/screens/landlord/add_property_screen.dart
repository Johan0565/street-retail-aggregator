import 'package:flutter/material.dart';
import '../../../services/property_service.dart';

class AddPropertyScreen extends StatefulWidget {
  const AddPropertyScreen({super.key});

  @override
  State<AddPropertyScreen> createState() => _AddPropertyScreenState();
}

class _AddPropertyScreenState extends State<AddPropertyScreen> {
  final _formKey = GlobalKey<FormState>();
  final PropertyService _propertyService = PropertyService();
  final Color _primaryOrange = const Color(0xFFFF8C00);

  // Контроллеры для текстовых полей
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _powerController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  // Состояния для переключателей (тегов)
  bool _hasWater = false;
  bool _hasVentilation = false;
  bool _hasSeparateEntrance = false;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _addressController.dispose();
    _priceController.dispose();
    _powerController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    // Проверяем, что все обязательные поля заполнены
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final success = await _propertyService.createProperty(
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      address: _addressController.text.trim(),
      pricePerMonth: int.parse(_priceController.text.trim()),
      powerKw: double.parse(_powerController.text.trim()),
      hasWater: _hasWater,
      hasVentilation: _hasVentilation,
      hasSeparateEntrance: _hasSeparateEntrance,
    );

    setState(() => _isSubmitting = false);

    if (success) {
      if (!mounted) return;
      Navigator.pop(context); // Закрываем экран
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Помещение успешно опубликовано!'), backgroundColor: Colors.green),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка при публикации. Проверьте соединение.'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Новое помещение', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Основная информация', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                // Название
                _buildTextField(
                  controller: _titleController,
                  label: 'Заголовок объявления',
                  hint: 'Например: Помещение свободного назначения 50 м²',
                  icon: Icons.title,
                ),
                const SizedBox(height: 16),

                // Адрес
                _buildTextField(
                  controller: _addressController,
                  label: 'Адрес',
                  hint: 'г. Москва, ул. Ленина, д. 1',
                  icon: Icons.location_on_outlined,
                ),
                const SizedBox(height: 16),

                // Цена и Электричество (в один ряд для красоты)
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _priceController,
                        label: 'Цена (₽/мес)',
                        hint: '150000',
                        icon: Icons.currency_ruble,
                        isNumber: true,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _powerController,
                        label: 'Мощность (кВт)',
                        hint: '15.0',
                        icon: Icons.bolt,
                        isNumber: true,
                      ),
                    ),
                  ],
                ),

                const Divider(height: 48),

                const Text('Технические параметры (Теги)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Отметьте, что есть в помещении. Это поможет алгоритму найти идеального арендатора.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 16),

                // Переключатели
                _buildSwitch(
                  title: 'Мокрая точка (Вода)',
                  value: _hasWater,
                  icon: Icons.water_drop_outlined,
                  onChanged: (val) => setState(() => _hasWater = val),
                ),
                _buildSwitch(
                  title: 'Промышленная вытяжка',
                  value: _hasVentilation,
                  icon: Icons.air,
                  onChanged: (val) => setState(() => _hasVentilation = val),
                ),
                _buildSwitch(
                  title: 'Отдельный вход',
                  value: _hasSeparateEntrance,
                  icon: Icons.door_front_door_outlined,
                  onChanged: (val) => setState(() => _hasSeparateEntrance = val),
                ),

                const Divider(height: 48),

                const Text('Детальное описание', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                // Описание
                TextFormField(
                  controller: _descController,
                  maxLines: 5,
                  validator: (value) => value!.isEmpty ? 'Заполните это поле' : null,
                  decoration: InputDecoration(
                    hintText: 'Опишите преимущества, трафик, соседство...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: _primaryOrange, width: 2),
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // Кнопка публикации
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black, // Черная кнопка, как в деталях помещения
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Опубликовать помещение', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Вспомогательный виджет для текстовых полей
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isNumber = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      validator: (value) => value!.isEmpty ? 'Заполните поле' : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.grey),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _primaryOrange, width: 2),
        ),
      ),
    );
  }

  // Вспомогательный виджет для красивых переключателей
  Widget _buildSwitch({
    required String title,
    required bool value,
    required IconData icon,
    required Function(bool) onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        secondary: Icon(icon, color: _primaryOrange),
        activeColor: _primaryOrange,
        value: value,
        onChanged: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}