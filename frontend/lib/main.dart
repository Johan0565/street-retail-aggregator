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
      home: const SplashScreen(),
    );
  }
}

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
    await Future.delayed(const Duration(milliseconds: 500));

    final auth = AuthService();

    String? role = await auth.checkAutoLogin();

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
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LandlordMainScreen())
      );
    } else {
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
        child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
      ),
    );
  }
}