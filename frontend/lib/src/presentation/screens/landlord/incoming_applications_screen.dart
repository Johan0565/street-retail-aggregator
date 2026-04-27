import 'package:flutter/material.dart';
import '../../../domain/application_model.dart';
import '../../../services/application_service.dart';
import '../chat/chat_screen.dart';

class IncomingApplicationsScreen extends StatefulWidget {
  const IncomingApplicationsScreen({super.key});

  @override
  State<IncomingApplicationsScreen> createState() => _IncomingApplicationsScreenState();
}

class _IncomingApplicationsScreenState extends State<IncomingApplicationsScreen> {
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
      _applicationsFuture = _applicationService.getIncomingApplications();
    });
  }

  // --- ЛОГИКА ФИЛЬТРАЦИИ И СОРТИРОВКИ ---
  List<ApplicationModel> _applyFilters(List<ApplicationModel> apps) {
    var filtered = apps.toList();

    // 1. Фильтр по статусу
    if (_statusFilter != 'ALL') {
      filtered = filtered.where((a) => a.status == _statusFilter).toList();
    }

    // 2. Фильтр по наличию письма (ищем те, где строка не пустая)
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

                  // Разнообразие: Только с письмом
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
                        setState(() {}); // Перерисовываем главный экран с новыми фильтрами
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

  // Вспомогательный виджет для чипов статуса
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

  // --- СТАРЫЕ МЕТОДЫ (Без изменений) ---
  Future<void> _changeStatus(int id, String newStatus, {String? reason}) async {
    final success = await _applicationService.updateApplicationStatus(id, newStatus, rejectionReason: reason);
    if (success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newStatus == 'ACCEPTED' ? 'Заявка одобрена' : 'Заявка отклонена'),
          backgroundColor: newStatus == 'ACCEPTED' ? Colors.green : Colors.red,
        ),
      );
      _loadApplications();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка при изменении статуса'), backgroundColor: Colors.red),
      );
    }
  }

  void _showRejectionDialog(int applicationId) {
    final TextEditingController reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Причина отказа', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Опишите причину отказа (необязательно)...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _primaryOrange, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена', style: TextStyle(color: Colors.black54))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _changeStatus(applicationId, 'REJECTED', reason: reasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Отклонить заявку', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  (String, Color) _getStatusInfo(String status) {
    switch (status) {
      case 'PENDING': return ('Ждет ответа', Colors.orange);
      case 'REVIEWING': return ('Изучается', Colors.blue);
      case 'ACCEPTED': return ('Одобрено', Colors.green);
      case 'REJECTED': return ('Отклонено', Colors.red);
      default: return (status, Colors.black);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Входящие заявки', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        actions: [
          // КНОПКА ФИЛЬТРА В APPBAR
          IconButton(
            icon: Icon(
              // Если фильтры изменены, показываем закрашенную иконку
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
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mail_outline, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text('Входящих заявок пока нет', style: TextStyle(color: Colors.grey, fontSize: 18)),
                ],
              ),
            );
          }

          // ПРИМЕНЯЕМ ФИЛЬТРЫ К ДАННЫМ
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
            onRefresh: () async => _loadApplications(),
            child: ListView.separated(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120),
              itemCount: applications.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final app = applications[index];
                final (statusText, statusColor) = _getStatusInfo(app.status);
                final canRespond = app.status == 'PENDING' || app.status == 'REVIEWING';

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
                        content: const Text('Вы уверены, что хотите удалить эту заявку из истории? Она также исчезнет у арендатора.'),
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
                      _loadApplications();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                            // Красивое отображение даты
                            Text(app.createdAt.split('T')[0] + ' ' + app.createdAt.split('T')[1].substring(0, 5), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text('Объект: ${app.property.title}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(app.property.address, style: const TextStyle(color: Colors.grey, fontSize: 14)),
  
                        const Divider(height: 32),
  
                        Row(
                          children: [
                            CircleAvatar(radius: 20, backgroundColor: Colors.blue.withOpacity(0.1), child: const Icon(Icons.person, color: Colors.blue)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(app.tenantName ?? 'Имя не указано', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text(app.tenantPhone ?? 'Телефон не указан', style: const TextStyle(color: Colors.black87, fontSize: 14)),
                                ],
                              ),
                            ),
                            // КНОПКА ЧАТА ДЛЯ ВЛАДЕЛЬЦА
                            IconButton(
                              icon: const Icon(Icons.chat_outlined, color: Color(0xFFFF8C00)),
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
                              tooltip: 'Написать арендатору',
                            ),
                          ],
                        ),
  
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Сопроводительное письмо:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(app.coverLetter.isNotEmpty ? app.coverLetter : 'Без сопроводительного письма', style: const TextStyle(fontStyle: FontStyle.italic)),
                            ],
                          ),
                        ),
  
                        if (canRespond) ...[
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _showRejectionDialog(app.id),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    side: const BorderSide(color: Colors.red),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Отклонить', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => _changeStatus(app.id, 'ACCEPTED'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Принять', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
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