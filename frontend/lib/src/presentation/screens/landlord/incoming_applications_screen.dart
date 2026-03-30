import 'package:flutter/material.dart';

class IncomingApplicationsScreen extends StatelessWidget {
  const IncomingApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📩 Входящие заявки'), backgroundColor: Colors.white, elevation: 0,),
      body: const Center(child: Text('Здесь будут заявки от Арендаторов')),
    );
  }
}