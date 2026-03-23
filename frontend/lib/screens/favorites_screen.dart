import 'package:flutter/material.dart';
import 'package:frontend/screens/property.dart';
import '../service/favorite_service.dart';
import 'property_details_screen.dart'; // Чтобы открывать детали помещения

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final FavoriteService _favoriteService = FavoriteService();
  late Future<List<Property>> _favoritesFuture;
  final Color _primaryOrange = const Color(0xFFFF8C00);

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  void _loadFavorites() {
    setState(() {
      _favoritesFuture = _favoriteService.getMyFavorites();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Избранное', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: FutureBuilder<List<Property>>(
        future: _favoritesFuture,
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
                  Icon(Icons.favorite_border, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text('У вас пока нет избранных', style: TextStyle(color: Colors.grey, fontSize: 18)),
                ],
              ),
            );
          }

          final properties = snapshot.data!;

          return RefreshIndicator(
            color: _primaryOrange,
            onRefresh: () async => _loadFavorites(),
            child: ListView.separated(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100),
              itemCount: properties.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final property = properties[index];

                return GestureDetector(
                  onTap: () {
                    // При клике открываем детальный экран
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PropertyDetailsScreen(property: property),
                      ),
                    ).then((_) {
                      // Когда возвращаемся назад, обновляем список (вдруг мы убрали лайк)
                      _loadFavorites();
                    });
                  },
                  child: Container(
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
                        // Заглушка картинки
                        Container(
                          height: 120,
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                          ),
                          child: const Icon(Icons.storefront, size: 40, color: Colors.black26),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${property.pricePerMonth} ₽ / мес',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primaryOrange),
                                  ),
                                  Icon(Icons.favorite, color: _primaryOrange, size: 24),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                property.title,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.location_on, size: 14, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      property.address,
                                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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