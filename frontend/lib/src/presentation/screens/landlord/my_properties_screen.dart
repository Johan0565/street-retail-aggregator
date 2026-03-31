import 'package:flutter/material.dart';
import '../../../domain/property.dart';
import '../../../services/property_service.dart';

class MyPropertiesScreen extends StatefulWidget {
  const MyPropertiesScreen({super.key});

  @override
  State<MyPropertiesScreen> createState() => _MyPropertiesScreenState();
}

class _MyPropertiesScreenState extends State<MyPropertiesScreen> {
  final PropertyService _propertyService = PropertyService();
  late Future<List<Property>> _propertiesFuture;
  final Color _primaryOrange = const Color(0xFFFF8C00);

  @override
  void initState() {
    super.initState();
    _loadProperties();
  }

  // Загрузка списка объектов
  void _loadProperties() {
    setState(() {
      _propertiesFuture = _propertyService.getMyProperties();
    });
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
      _loadProperties(); // Перезагружаем список
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
      ),
      body: FutureBuilder<List<Property>>(
        future: _propertiesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.black));
          } else if (snapshot.hasError) {
            return const Center(child: Text('Ошибка при загрузке данных'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.business_outlined, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text('У вас пока нет добавленных объектов', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          final properties = snapshot.data!;

          return RefreshIndicator(
            color: _primaryOrange,
            onRefresh: () async => _loadProperties(),
            child: ListView.separated(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120),
              itemCount: properties.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final property = properties[index];

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Иконка-заглушка для помещения
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: _primaryOrange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.storefront, color: _primaryOrange, size: 30),
                      ),
                      const SizedBox(width: 16),

                      // Информация об объекте
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              property.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              property.address,
                              style: const TextStyle(color: Colors.grey, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${property.pricePerMonth} ₽/мес',
                              style: TextStyle(color: _primaryOrange, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ],
                        ),
                      ),

                      // КНОПКА УДАЛЕНИЯ
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _deleteProperty(property.id, property.title),
                        tooltip: 'Удалить объект',
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}