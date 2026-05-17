import 'package:flutter/material.dart';
import 'favorites_screen.dart';
import 'map_screen.dart';
import 'my_applications_screen.dart';
import 'profile_screen.dart';
import 'search_profiles_screen.dart';

class TenantMainScreen extends StatefulWidget {
  const TenantMainScreen({super.key});

  @override
  State<TenantMainScreen> createState() => _TenantMainScreenState();
}

class _TenantMainScreenState extends State<TenantMainScreen> {
  int _selectedIndex = 0;

  final Color _primaryOrange = const Color(0xFFFF8C00);

  // Ключ для доступа к стейту "Избранное" — нужен, чтобы перезагружать
  // список при переходе на вкладку (IndexedStack сохраняет состояние,
  // поэтому добавленное из деталей помещения не появлялось без рестарта).
  final GlobalKey<FavoritesScreenState> _favoritesKey = GlobalKey<FavoritesScreenState>();
  // Ключ к стейту карты — чтобы подхватывать новые проекты поиска без перезапуска.
  final GlobalKey<MapScreenState> _mapKey = GlobalKey<MapScreenState>();
  // Ключ к стейту «Заявки» — чтобы свеже-отправленная заявка появлялась
  // в списке без перезахода в приложение.
  final GlobalKey<MyApplicationsScreenState> _applicationsKey = GlobalKey<MyApplicationsScreenState>();

  // Список экранов для каждой вкладки
  late final List<Widget> _screens = [
    MapScreen(key: _mapKey),
    FavoritesScreen(key: _favoritesKey),
    MyApplicationsScreen(key: _applicationsKey),
    const SearchProfilesScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // ВАЖНО: это свойство позволяет телу экрана (например, карте)
      // отрисовываться ПОД плавающей навигационной панелью
      extendBody: true,

      // ИСПРАВЛЕНИЕ ЗДЕСЬ: Используем IndexedStack для сохранения состояния экранов!
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),

      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.only(left: 12, right: 12, bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
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
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(icon: Icons.map_outlined, activeIcon: Icons.map_rounded, label: 'Карта', index: 0),
              _buildNavItem(icon: Icons.favorite_border, activeIcon: Icons.favorite, label: 'Избранное', index: 1),
              _buildNavItem(icon: Icons.mail_outline, activeIcon: Icons.mail, label: 'Заявки', index: 2),
              _buildNavItem(icon: Icons.manage_search_rounded, activeIcon: Icons.manage_search, label: 'Проекты', index: 3),
              _buildNavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Профиль', index: 4),
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
        // При переходе на "Избранное" обновляем список,
        // чтобы свежедобавленные помещения были видны без перезапуска.
        if (index == 1) {
          _favoritesKey.currentState?.loadFavorites();
        }
        // При переходе на "Заявки" — перетягиваем список с сервера,
        // чтобы только что отправленная заявка появилась без перезахода.
        if (index == 2) {
          _applicationsKey.currentState?.loadApplications();
        }
        // При возврате на карту — подтягиваем свежий список проектов поиска,
        // чтобы dropdown "Выбрать проект поиска" появлялся сразу после
        // создания первого проекта (без перезапуска приложения).
        if (index == 0) {
          _mapKey.currentState?.reloadProfiles();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _primaryOrange.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? _primaryOrange : Colors.white70,
              size: 24,
            ),
            // Анимация появления текста при выделении
            if (isSelected) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: _primaryOrange,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}