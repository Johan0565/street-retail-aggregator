import 'package:flutter/material.dart';
import '../service/application_service.dart';
import 'application_model.dart';


class MyApplicationsScreen extends StatefulWidget {
  const MyApplicationsScreen({super.key});

  @override
  State<MyApplicationsScreen> createState() => _MyApplicationsScreenState();
}

class _MyApplicationsScreenState extends State<MyApplicationsScreen> {
  final ApplicationService _applicationService = ApplicationService();
  late Future<List<ApplicationModel>> _applicationsFuture;

  final Color _primaryOrange = const Color(0xFFFF8C00);

  @override
  void initState() {
    super.initState();
    _applicationsFuture = _applicationService.getMyApplications();
  }

  // Метод для перевода статуса на русский и выбора цвета
  (String, Color) _getStatusInfo(String status) {
    switch (status) {
      case 'PENDING':
        return ('На рассмотрении', Colors.grey[600]!);
      case 'REVIEWING':
        return ('Изучается', Colors.blue);
      case 'ACCEPTED':
        return ('Одобрено', Colors.green);
      case 'REJECTED':
        return ('Отклонено', Colors.red);
      default:
        return (status, Colors.black);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Мои заявки', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: FutureBuilder<List<ApplicationModel>>(
        future: _applicationsFuture,
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
                  Icon(Icons.inbox_outlined, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text('У вас пока нет заявок', style: TextStyle(color: Colors.grey, fontSize: 18)),
                ],
              ),
            );
          }

          final applications = snapshot.data!;

          return RefreshIndicator(
            color: _primaryOrange,
            onRefresh: () async {
              setState(() {
                _applicationsFuture = _applicationService.getMyApplications();
              });
            },
            child: ListView.separated(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100), // Отступ снизу для нижней панели
              itemCount: applications.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final app = applications[index];
                final (statusText, statusColor) = _getStatusInfo(app.status);

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[200]!),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Шапка карточки: Статус и Дата
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          Text(
                            app.createdAt.split('T')[0], // Показываем только дату
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Информация о помещении
                      Text(
                        app.property.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        app.property.address,
                        style: const TextStyle(color: Colors.grey, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${app.property.pricePerMonth} ₽ / мес',
                        style: TextStyle(color: _primaryOrange, fontWeight: FontWeight.bold, fontSize: 16),
                      ),

                      const Divider(height: 24),

                      // Сопроводительное письмо
                      const Text('Ваше письмо:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(
                        app.coverLetter,
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                        maxLines: 2, // Обрезаем длинный текст
                        overflow: TextOverflow.ellipsis,
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