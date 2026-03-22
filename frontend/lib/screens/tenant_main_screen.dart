import 'package:flutter/material.dart';

// Импортируем карту (перенесем ее код в отдельный файл чуть позже)
// import 'map_screen.dart';

class TenantMainScreen extends StatefulWidget {
  const TenantMainScreen({super.key});

  @override
  State<TenantMainScreen> createState() => _TenantMainScreenState();
}

class _TenantMainScreenState extends State<TenantMainScreen> {
  int _selectedIndex = 0;

  final Color _primaryOrange = const Color(0xFFFF8C00);

  // Список экранов для каждой вкладки
  final List<Widget> _screens = [
    const PlaceholderMapScreen(), // Заглушка для карты (заменим на твою Яндекс Карту)
    const Center(child: Text('Избранное', style: TextStyle(fontSize: 24))),
    const Center(child: Text('Мои заявки', style: TextStyle(fontSize: 24))),
    const Center(child: Text('Профиль', style: TextStyle(fontSize: 24))),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // ВАЖНО: это свойство позволяет телу экрана (например, карте)
      // отрисовываться ПОД плавающей навигационной панелью
      extendBody: true,

      body: _screens[_selectedIndex],

      // Плавающая панель навигации
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black87, // Темный стильный фон панели
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildNavItem(icon: Icons.map_outlined, activeIcon: Icons.map_rounded, label: 'Карта', index: 0),
              _buildNavItem(icon: Icons.favorite_border, activeIcon: Icons.favorite, label: 'Избранное', index: 1),
              _buildNavItem(icon: Icons.mail_outline, activeIcon: Icons.mail, label: 'Заявки', index: 2),
              _buildNavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Профиль', index: 3),
            ],
          ),
        ),
      ),
    );
  }

  // Метод для отрисовки отдельной кнопки в панели
  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
  }) {
    final isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _primaryOrange.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? _primaryOrange : Colors.white70,
              size: 26,
            ),
            // Анимация появления текста при выделении
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: _primaryOrange,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

// ВРЕМЕННАЯ ЗАГЛУШКА ДЛЯ КАРТЫ (чтобы код компилировался)
class PlaceholderMapScreen extends StatelessWidget {
  const PlaceholderMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: Text(
          'Здесь будет Yandex MapKit',
          style: TextStyle(color: Colors.grey, fontSize: 18),
        ),
      ),
    );
  }
}