import 'package:flutter/material.dart';

// ИМПОРТЫ НОВЫХ ЭКРАНОВ (проверь пути относительно src)
import 'my_properties_screen.dart';
import 'add_property_screen.dart';
import 'incoming_applications_screen.dart';
// Используем существующий профиль, он универсальный
import '../tenant/profile_screen.dart'; // <-- ПРОВЕРЬ ПУТЬ

class LandlordMainScreen extends StatefulWidget {
  const LandlordMainScreen({super.key});

  @override
  State<LandlordMainScreen> createState() => _LandlordMainScreenState();
}

class _LandlordMainScreenState extends State<LandlordMainScreen> {
  int _selectedIndex = 0;
  final Color _primaryOrange = const Color(0xFFFF8C00);

  // Список экранов для вкладок
  final List<Widget> _screens = [
    const MyPropertiesScreen(),         // 0: Мои объекты
    const PlaceholderAddProperty(),      // 1: Заглушка (чтобы работала навигация, сам экран открывается кнопкой)
    const IncomingApplicationsScreen(),   // 2: Заявки
    const ProfileScreen(),              // 3: Профиль
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // ВАЖНО: тело экрана заходит ПОД панель навигации (Floating UI)
      extendBody: true,

      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),

      // Большая центральная кнопка "Добавить"
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Открываем экран добавления как модальное окно (сверху вниз)
          _openAddPropertyScreen();
        },
        backgroundColor: _primaryOrange,
        elevation: 10,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 36),
      ),

      // Плавающая панель навигации (как у Арендатора)
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black, // Стильный черный фон
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 0: Мои объекты
              _buildNavItem(icon: Icons.business_outlined, activeIcon: Icons.business_center, label: 'Объекты', index: 0),

              // Пропуск для центральной кнопки (чтобы иконки не наезжали)
              const SizedBox(width: 48),

              // 2: Заявки
              _buildNavItem(icon: Icons.mail_outline, activeIcon: Icons.mail_rounded, label: 'Заявки', index: 2),
              // 3: Профиль
              _buildNavItem(icon: Icons.person_outline, activeIcon: Icons.person_rounded, label: 'Профиль', index: 3),
            ],
          ),
        ),
      ),
    );
  }

  // Метод для открытия экрана добавления
  void _openAddPropertyScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true, // Кнопка "Закрыть" вместо "Назад"
        builder: (context) => const AddPropertyScreen(),
      ),
    );
  }

  // Вспомогательный метод для отрисовки пункта меню (как у Арендатора)
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _primaryOrange.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? _primaryOrange : Colors.white60,
              size: 26,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(color: _primaryOrange, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

// Временная заглушка для 1-го индекса IndexedStack
class PlaceholderAddProperty extends StatelessWidget {
  const PlaceholderAddProperty({super.key});
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}