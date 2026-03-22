import 'package:flutter/material.dart';

class LandlordMainScreen extends StatelessWidget {
  const LandlordMainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои объекты (Арендодатель)'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text('Здесь будет интерфейс Арендодателя', style: TextStyle(fontSize: 20)),
      ),
    );
  }
}