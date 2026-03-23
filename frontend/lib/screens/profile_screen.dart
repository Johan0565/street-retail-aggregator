import 'package:flutter/material.dart';
import 'user_profile.dart';
import '../service/auth_service.dart';
import 'login_screen.dart'; // Для перехода при выходе

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  late Future<UserProfile?> _profileFuture;
  final Color _primaryOrange = const Color(0xFFFF8C00);

  @override
  void initState() {
    super.initState();
    _profileFuture = _authService.getCurrentUserProfile();
  }

  // Метод выхода из аккаунта
  void _handleLogout() async {
    // Показываем диалог подтверждения
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
      // Очищаем историю навигации и перекидываем на экран логина
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false, // Удаляем все предыдущие экраны
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Профиль', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: FutureBuilder<UserProfile?>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.black));
          }

          // Если данные не загрузились
          final profile = snapshot.data ?? UserProfile(
              id: 0,
              name: 'Арендатор',
              phone: '-',
              inn: '-',
              businessCategory: 'Загрузка...'
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
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
                const SizedBox(height: 32),

                // ОБНОВЛЕННЫЕ КАРТОЧКИ С ДАННЫМИ
                _buildInfoCard(Icons.storefront_outlined, 'Ниша', profile.businessCategory),
                const SizedBox(height: 16),
                _buildInfoCard(Icons.phone_outlined, 'Телефон', profile.phone),
                const SizedBox(height: 16),
                _buildInfoCard(Icons.numbers, 'ИНН', profile.inn),

                const SizedBox(height: 40),

                // Кнопка выхода
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _handleLogout,
                    icon: const Icon(Icons.logout, color: Colors.red),
                    label: const Text('Выйти из аккаунта', style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

  // Вспомогательный виджет для отрисовки полей (Email, Телефон и тд)
  Widget _buildInfoCard(IconData icon, String title, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.black87, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}