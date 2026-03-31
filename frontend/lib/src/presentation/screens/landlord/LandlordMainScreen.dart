import 'package:flutter/material.dart';

// ИМПОРТЫ ЭКРАНОВ (Обязательно проверь пути!)
import '../tenant/map_screen.dart'; // <-- Путь до твоей карты
import 'my_properties_screen.dart';
import 'add_property_screen.dart';
import 'incoming_applications_screen.dart';
import '../tenant/profile_screen.dart'; // Универсальный профиль

class LandlordMainScreen extends StatefulWidget {
  const LandlordMainScreen({super.key});

  @override
  State<LandlordMainScreen> createState() => _LandlordMainScreenState();
}

class _LandlordMainScreenState extends State<LandlordMainScreen> {
  int _selectedIndex = 0;
  final Color _primaryOrange = const Color(0xFFFF8C00);

  final List<Widget> _screens = [
    const MapScreen(isLandlordMode: true),
    const MyPropertiesScreen(),
    const IncomingApplicationsScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      extendBody: true,

      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddPropertyScreen,
        backgroundColor: _primaryOrange,
        elevation: 10,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 36),
      ),

      // ИСПРАВЛЕННАЯ ПЛАВАЮЩАЯ ПАНЕЛЬ НАВИГАЦИИ (СТИЛЬ КАК У TENANT)
      bottomNavigationBar: SafeArea(
        child: Container(
          // 1. Сделали отступы как у Арендатора
          margin: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
          // 2. Вернули вертикальный паддинг
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            // 3. Вернули цвет black87 (чуть прозрачный черный)
            color: Colors.black87,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20, // Вернули размытие тени до 20
                offset: const Offset(0, 10), // Смещение тени как у Арендатора
              ),
            ],
          ),
          child: Row(
            children: [
              // --- ЛЕВАЯ ЖЕСТКАЯ ПОЛОВИНА ---
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavItem(icon: Icons.map_outlined, activeIcon: Icons.map_rounded, label: 'Карта', index: 0),
                    _buildNavItem(icon: Icons.business_outlined, activeIcon: Icons.business_center, label: 'Объекты', index: 1),
                  ],
                ),
              ),

              // --- ЦЕНТРАЛЬНОЕ МЕСТО ПОД КНОПКУ (Зафиксировано) ---
              const SizedBox(width: 56),

              // --- ПРАВАЯ ЖЕСТКАЯ ПОЛОВИНА ---
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavItem(icon: Icons.mail_outline, activeIcon: Icons.mail_rounded, label: 'Заявки', index: 2),
                    _buildNavItem(icon: Icons.person_outline, activeIcon: Icons.person_rounded, label: 'Профиль', index: 3),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openAddPropertyScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => const AddPropertyScreen(),
      ),
    );
  }

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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _primaryOrange.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min, // Убеждаемся, что кнопка не растягивается бесконечно
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? _primaryOrange : Colors.white60,
              size: 24,
            ),
            if (isSelected) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(color: _primaryOrange, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ]
          ],
        ),
      ),
    );
  }
}