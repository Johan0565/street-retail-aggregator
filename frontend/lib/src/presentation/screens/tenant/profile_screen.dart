import 'package:flutter/material.dart';
import '../../../domain/user_profile.dart';
import '../../../services/auth_service.dart';
import '../../../services/category_service.dart';
import '../auth/login_screen.dart';
import '../../../domain/business_category.dart';


class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  late Future<UserProfile?> _profileFuture;

  final Color _primaryOrange = const Color(0xFFFF8C00);
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // Метод для перезагрузки профиля после редактирования
  void _loadProfile() {
    setState(() {
      _profileFuture = _authService.getCurrentUserProfile();
    });
  }

  void _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выход'),
        content: const Text('Вы уверены, что хотите выйти из аккаунта?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.black54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Выйти', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await _authService.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
      );
    }
  }

  // --- НОВЫЙ МЕТОД: Служба поддержки ---
  void _showSupportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Служба поддержки', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.telegram, color: Colors.blue, size: 36),
              title: const Text('Telegram', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('@MosRetailSupport'),
              onTap: () {
                // В будущем здесь можно добавить url_launcher для открытия ТГ
              },
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.email, color: _primaryOrange, size: 36),
              title: const Text('Email', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('support@mosretail.ru'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  // --- НОВЫЙ МЕТОД: О приложении ---
  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Retail Aggregator',
      applicationVersion: 'Версия 1.0.0 (Beta)',
      applicationIcon: Image.asset('assets/Logo.png', width: 50, height: 50),
      applicationLegalese: '© 2026 MosWorkout Retail.\nВсе права защищены.',
    );
  }

  void _showEditProfileSheet(UserProfile currentProfile) {
    final nameController = TextEditingController(text: currentProfile.name);
    final phoneController = TextEditingController(text: currentProfile.phone);

    // Состояние для выпадающего списка
    int? selectedCategoryId = currentProfile.businessCategoryId;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateSheet) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Редактировать профиль', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Имя / Название компании',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Телефон',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // НОВЫЙ БЛОК: Выбор ниши (загружаем асинхронно)
                  FutureBuilder<List<BusinessCategory>>(
                    future: CategoryService().getCategories(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final categories = snapshot.data ?? [];

                      // Проверяем, существует ли сохраненный ID в загруженном списке
                      // Если нет (например, категорию удалили на бэке), сбрасываем выбор
                      if (selectedCategoryId != null && !categories.any((c) => c.id == selectedCategoryId)) {
                        selectedCategoryId = null;
                      }

                      return DropdownButtonFormField<int>(
                        value: selectedCategoryId,
                        decoration: const InputDecoration(
                          labelText: 'Целевая ниша бизнеса',
                          prefixIcon: Icon(Icons.storefront),
                          border: OutlineInputBorder(),
                        ),
                        items: categories.map((category) {
                          return DropdownMenuItem<int>(
                            value: category.id,
                            child: Text(category.name),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setStateSheet(() => selectedCategoryId = value);
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                        setStateSheet(() => isSubmitting = true);

                        final success = await _authService.updateProfile(
                          nameController.text.trim(),
                          phoneController.text.trim(),
                          selectedCategoryId, // Передаем выбранный ID на бэкенд
                        );

                        setStateSheet(() => isSubmitting = false);

                        if (success) {
                          Navigator.pop(context);
                          _loadProfile();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Данные успешно обновлены'), backgroundColor: Colors.green),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ошибка при сохранении'), backgroundColor: Colors.red),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryOrange,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isSubmitting
                          ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Сохранить', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Мой профиль', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: FutureBuilder<UserProfile?>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.black));
          }

          final profile = snapshot.data ?? UserProfile(
              id: 0,
              name: 'Арендатор',
              phone: 'Не указан',
              inn: 'Не указан',
              businessCategory: 'Не выбрана'
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. ШАПКА
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: _primaryOrange.withOpacity(0.1),
                        child: Text(
                          profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                          style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: _primaryOrange),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        profile.name,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Арендатор', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 2. ДАННЫЕ
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      children: [
                        _buildDataRow(Icons.storefront_outlined, 'Ниша', profile.businessCategory),
                        const Divider(height: 1, indent: 56),
                        _buildDataRow(Icons.phone_outlined, 'Телефон', profile.phone),
                        const Divider(height: 1, indent: 56),
                        _buildDataRow(Icons.numbers, 'ИНН', profile.inn),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 3. МЕНЮ НАСТРОЕК
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      children: [
                        // Привязали вызов формы редактирования!
                        _buildMenuTile(
                          icon: Icons.edit_outlined,
                          title: 'Редактировать данные',
                          onTap: () => _showEditProfileSheet(profile),
                        ),
                        const Divider(height: 1, indent: 56),

                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
                            child: const Icon(Icons.notifications_none, color: Colors.black87),
                          ),
                          title: const Text('Уведомления', style: TextStyle(fontWeight: FontWeight.w600)),
                          trailing: Switch(
                            value: _notificationsEnabled,
                            activeColor: _primaryOrange,
                            onChanged: (value) {
                              setState(() => _notificationsEnabled = value);
                            },
                          ),
                        ),

                        const Divider(height: 1, indent: 56),
                        // Привязали вызов поддержки!
                        _buildMenuTile(
                          icon: Icons.help_outline,
                          title: 'Служба поддержки',
                          onTap: _showSupportDialog,
                        ),
                        const Divider(height: 1, indent: 56),
                        // Привязали вызов окна "О приложении"!
                        _buildMenuTile(
                          icon: Icons.info_outline,
                          title: 'О приложении',
                          onTap: _showAboutDialog,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // 4. ВЫХОД
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _handleLogout,
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: const Text('Выйти из аккаунта', style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.red, width: 1.5),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDataRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.black54, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile({required IconData icon, required String title, VoidCallback? onTap}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.black87),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}