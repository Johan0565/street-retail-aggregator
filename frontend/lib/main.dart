import 'package:flutter/material.dart';
import 'package:frontend/service/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/tenant_main_screen.dart';
import 'service/auth_service.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Retail Aggregator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF8C00)),
        useMaterial3: true,
      ),
      // Теперь стартуем не с LoginScreen, а с загрузочного экрана
      home: const SplashScreen(),
    );
  }
}

// Умный экран-маршрутизатор
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Ждем долю секунды для красивой анимации (не обязательно, но выглядит приятнее)
    await Future.delayed(const Duration(milliseconds: 500));

    // Проверяем, нужно ли делать автологин
    final role = await AuthService().checkAutoLogin();

    if (!mounted) return;

    if (role == 'TENANT') {
      // Пользователь уже был залогинен как арендатор! Кидаем на карту.
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TenantMainScreen())
      );
    } else if (role == 'LANDLORD') {
      // Пока экрана арендодателя нет, кидаем на заглушку
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const Scaffold(body: Center(child: Text('Экран арендодателя скоро будет'))))
      );
    } else {
      // Токена нет или галочка не стояла -> на экран авторизации
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen())
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        // Оранжевая крутилка во время проверки токена
        child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
      ),
    );
  }
}