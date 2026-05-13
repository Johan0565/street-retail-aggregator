import 'package:flutter/material.dart';
import 'package:frontend/src/presentation/screens/auth/login_screen.dart';
import 'package:frontend/src/presentation/screens/landlord/LandlordMainScreen.dart';
import 'package:frontend/src/presentation/screens/tenant/tenant_main_screen.dart';
import 'package:frontend/src/services/auth_service.dart';

import 'package:frontend/src/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().initialize();
  NotificationService().handleIncomingMessages();
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

    final auth = AuthService();
    // Сначала пытаемся продолжить активную сессию.
    String? role = await auth.checkAutoLogin();

    // Если активный токен протух, но в списке сохранённых аккаунтов есть валидные —
    // тихо восстанавливаем самый недавний.
    if (role == null) {
      final accounts = await auth.getSavedAccounts();
      for (final acc in accounts) {
        final resumed = await auth.resumeSavedAccount(acc.email);
        if (resumed != null) {
          role = resumed;
          break;
        }
      }
    }

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
          MaterialPageRoute(builder: (_) => const LandlordMainScreen())
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