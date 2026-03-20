import 'package:flutter/material.dart';
// 1. Добавляем импорт нашего нового экрана:
import 'screens/login_screen.dart';
// Если у тебя MapScreen остался в этом же файле, YandexMapKit тоже оставляем
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF8C00)), // Можно сразу задать оранжевый как основной
        useMaterial3: true,
      ),
      // 2. МЕНЯЕМ СТАРТОВЫЙ ЭКРАН ЗДЕСЬ:
      home: const LoginScreen(),
    );
  }
}

// ... дальше ниже остается твой класс MapScreen ...