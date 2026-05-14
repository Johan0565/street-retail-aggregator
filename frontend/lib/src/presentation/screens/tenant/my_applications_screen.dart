import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../../../domain/application_model.dart';
import '../../../services/application_service.dart';
import '../chat/chat_screen.dart';

class MyApplicationsScreen extends StatefulWidget {
  const MyApplicationsScreen({super.key});

  @override
  State<MyApplicationsScreen> createState() => _MyApplicationsScreenState();
}

class _MyApplicationsScreenState extends State<MyApplicationsScreen> {
  final ApplicationService _applicationService = ApplicationService();
  late Future<List<ApplicationModel>> _applicationsFuture;
  final Color _primaryOrange = const Color(0xFFFF8C00);

  // --- ПЕРЕМЕННЫЕ ДЛЯ ФИЛЬТРОВ ---
  String _sortOrder = 'desc'; // 'desc' - сначала новые, 'asc' - сначала старые
  String _statusFilter = 'ALL'; // 'ALL', 'PENDING', 'ACCEPTED', 'REJECTED'
  bool _onlyWithLetter = false; // Только с сопроводительным письмом

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  void _loadApplications() {
    setState(() {
      _applicationsFuture = _applicationService.getMyApplications();
    });
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

  // --- ЛОГИКА ФИЛЬТРАЦИИ И СОРТИРОВКИ ---
  List<ApplicationModel> _applyFilters(List<ApplicationModel> apps) {
    var filtered = apps.toList();

    // 1. Фильтр по статусу
    if (_statusFilter != 'ALL') {
      filtered = filtered.where((a) => a.status == _statusFilter).toList();
    }

    // 2. Фильтр по наличию письма
    if (_onlyWithLetter) {
      filtered = filtered.where((a) => a.coverLetter.trim().isNotEmpty).toList();
    }

    // 3. Сортировка по дате
    filtered.sort((a, b) {
      final dateA = DateTime.tryParse(a.createdAt) ?? DateTime.now();
      final dateB = DateTime.tryParse(b.createdAt) ?? DateTime.now();
      return _sortOrder == 'desc' ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
    });

    return filtered;
  }

  // --- ШТОРКА С НАСТРОЙКАМИ ФИЛЬТРОВ ---
  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Фильтры и сортировка', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),

                  // Сортировка по дате
                  const Text('По дате', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Сначала новые'),
                          selected: _sortOrder == 'desc',
                          selectedColor: _primaryOrange.withOpacity(0.2),
                          onSelected: (val) => setModalState(() => _sortOrder = 'desc'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Сначала старые'),
                          selected: _sortOrder == 'asc',
                          selectedColor: _primaryOrange.withOpacity(0.2),
                          onSelected: (val) => setModalState(() => _sortOrder = 'asc'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Статус заявки
                  const Text('Статус', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildStatusChip('Все', 'ALL', setModalState),
                      _buildStatusChip('На рассмотрении', 'PENDING', setModalState),
                      _buildStatusChip('Одобрено', 'ACCEPTED', setModalState),
                      _buildStatusChip('Отклонено', 'REJECTED', setModalState),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Только с письмом
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Только с сопроводительным письмом', style: TextStyle(fontWeight: FontWeight.bold)),
                    activeColor: _primaryOrange,
                    value: _onlyWithLetter,
                    onChanged: (val) => setModalState(() => _onlyWithLetter = val),
                  ),
                  const SizedBox(height: 32),

                  // Кнопка применения
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {}); // Перерисовываем экран
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Применить', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusChip(String label, String value, StateSetter setModalState) {
    return ChoiceChip(
      label: Text(label),
      selected: _statusFilter == value,
      selectedColor: _primaryOrange.withOpacity(0.2),
      onSelected: (selected) {
        if (selected) setModalState(() => _statusFilter = value);
      },
    );
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
        actions: [
          // КНОПКА ФИЛЬТРА В APPBAR
          IconButton(
            icon: Icon(
              (_sortOrder != 'desc' || _statusFilter != 'ALL' || _onlyWithLetter) ? Icons.filter_alt : Icons.filter_alt_outlined,
              color: (_sortOrder != 'desc' || _statusFilter != 'ALL' || _onlyWithLetter) ? _primaryOrange : Colors.black,
            ),
            onPressed: _showFilterSheet,
          ),
          const SizedBox(width: 8),
        ],
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

          // ПРИМЕНЯЕМ ФИЛЬТРЫ
          final applications = _applyFilters(snapshot.data!);

          if (applications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text('По вашим фильтрам ничего не найдено', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: _primaryOrange,
            onRefresh: () async {
              setState(() {
                _applicationsFuture = _applicationService.getMyApplications();
              });
            },
            child: ListView.separated(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100),
              itemCount: applications.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final app = applications[index];
                final (statusText, statusColor) = _getStatusInfo(app.status);

                return Dismissible(
                  key: Key('app_${app.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 32),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.delete_outline, color: Colors.white, size: 32),
                  ),
                  confirmDismiss: (direction) async {
                    if (app.status == 'ACCEPTED') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Нельзя удалить принятую заявку'), backgroundColor: Colors.orange),
                      );
                      return false;
                    }
                    return await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Удаление'),
                        content: const Text('Вы уверены, что хотите отозвать эту заявку? Она исчезнет из истории у вас и у владельца.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                  },
                  onDismissed: (direction) async {
                    final success = await _applicationService.deleteApplication(app.id);
                    if (success) {
                      setState(() {
                        _applicationsFuture = _applicationService.getMyApplications();
                      });
                    }
                  },
                  child: Container(
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
                              app.createdAt.split('T')[0] + ' ' + app.createdAt.split('T')[1].substring(0, 5),
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
                          app.coverLetter.isNotEmpty ? app.coverLetter : 'Без письма',
                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
  
                        // Причина отказа (выводится только если REJECTED)
                        if (app.status == 'REJECTED' && app.rejectionReason != null && app.rejectionReason!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.withOpacity(0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.info_outline, color: Colors.red, size: 16),
                                    SizedBox(width: 6),
                                    Text('Причина отказа:', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(app.rejectionReason!, style: const TextStyle(color: Colors.black87, fontSize: 14)),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatScreen(
                                    applicationId: app.id,
                                    applicationTitle: app.property.title,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.chat_bubble_outline, size: 20),
                            label: const Text('Чат с владельцем'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _primaryOrange,
                              side: BorderSide(color: _primaryOrange),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        if (app.status == 'ACCEPTED' &&
                            app.landlordPhone != null &&
                            app.landlordPhone!.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green.withOpacity(0.25)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.phone_outlined, color: Colors.green, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Контакт владельца',
                                        style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        app.landlordPhone!,
                                        style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Скопировать',
                                  icon: const Icon(Icons.copy, size: 18, color: Colors.green),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: app.landlordPhone!));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Номер скопирован'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
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