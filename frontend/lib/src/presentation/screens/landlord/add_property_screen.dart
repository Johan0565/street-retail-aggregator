import 'package:flutter/material.dart';
import '../../../services/property_service.dart';
import 'map_picker_screen.dart';

class AddPropertyScreen extends StatefulWidget {
  const AddPropertyScreen({super.key});

  @override
  State<AddPropertyScreen> createState() => _AddPropertyScreenState();
}

class _AddPropertyScreenState extends State<AddPropertyScreen> {
  final _formKey = GlobalKey<FormState>();
  final PropertyService _propertyService = PropertyService();
  final Color _primaryOrange = const Color(0xFFFF8C00);

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _powerController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  bool _hasWater = false;
  bool _hasVentilation = false;
  bool _hasSeparateEntrance = false;

  double? _selectedLat;
  double? _selectedLon;
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
    if (!_formKey.currentState!.validate()) return;

    if (_selectedLat == null || _selectedLon == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Обязательно укажите точку на карте!'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final success = await _propertyService.createProperty(
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        address: _addressController.text.trim(),
        pricePerMonth: int.parse(_priceController.text.trim()),
        powerKw: double.parse(_powerController.text.trim()),
        hasWater: _hasWater,
        hasVentilation: _hasVentilation,
        hasSeparateEntrance: _hasSeparateEntrance,
        latitude: _selectedLat!,
        longitude: _selectedLon!,
      );

      if (success) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Помещение опубликовано!'), backgroundColor: Colors.green),
        );
      } else {
        throw Exception('Ошибка сервера');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка при публикации. Проверьте данные.'), backgroundColor: Colors.red),
      );
    } finally {
      // Это ГАРАНТИРУЕТ, что загрузка прекратится в любом случае
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Новое помещение', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTextField(controller: _titleController, label: 'Заголовок', icon: Icons.title),
                const SizedBox(height: 16),

                // ОДНО ПОЛЕ АДРЕСА + КНОПКА КАРТЫ
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _addressController,
                        label: 'Введите адрес словами',
                        icon: Icons.location_on_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      height: 60,
                      width: 60,
                      decoration: BoxDecoration(
                        color: _selectedLat != null ? Colors.green.withOpacity(0.1) : _primaryOrange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _selectedLat != null ? Colors.green : _primaryOrange),
                      ),
                      child: IconButton(
                        icon: Icon(
                            _selectedLat != null ? Icons.check : Icons.map_outlined,
                            color: _selectedLat != null ? Colors.green : _primaryOrange,
                            size: 30
                        ),
                        onPressed: () async {
                          final result = await Navigator.push<Map<String, dynamic>>(
                            context,
                            MaterialPageRoute(builder: (context) => const MapPickerScreen()),
                          );
                          if (result != null) {
                            setState(() {
                              _selectedLat = result['latitude'];
                              _selectedLon = result['longitude'];
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (_selectedLat == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8, left: 12),
                    child: Text('Нажмите на карту, чтобы передать точные координаты ->', style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(child: _buildTextField(controller: _priceController, label: 'Цена (₽/мес)', icon: Icons.currency_ruble, isNumber: true)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildTextField(controller: _powerController, label: 'кВт', icon: Icons.bolt, isNumber: true)),
                  ],
                ),

                const Divider(height: 48),
                const Text('Параметры', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                _buildSwitch(title: 'Мокрая точка', value: _hasWater, icon: Icons.water_drop, onChanged: (v) => setState(() => _hasWater = v)),
                _buildSwitch(title: 'Вытяжка', value: _hasVentilation, icon: Icons.air, onChanged: (v) => setState(() => _hasVentilation = v)),
                _buildSwitch(title: 'Отдельный вход', value: _hasSeparateEntrance, icon: Icons.door_front_door, onChanged: (v) => setState(() => _hasSeparateEntrance = v)),

                const Divider(height: 48),
                TextFormField(
                  controller: _descController,
                  maxLines: 4,
                  validator: (value) => value!.isEmpty ? 'Заполните описание' : null,
                  decoration: InputDecoration(
                    labelText: 'Описание',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 40),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Опубликовать', style: TextStyle(fontSize: 18, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon, bool isNumber = false}) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      validator: (value) => value!.isEmpty ? 'Обязательное поле' : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildSwitch({required String title, required bool value, required IconData icon, required Function(bool) onChanged}) {
    return SwitchListTile(
      title: Text(title),
      secondary: Icon(icon, color: _primaryOrange),
      activeColor: _primaryOrange,
      value: value,
      onChanged: onChanged,
    );
  }
}