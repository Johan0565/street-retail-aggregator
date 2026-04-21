import 'package:flutter/foundation.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  Future<void> initialize() async {
    // В будущем здесь будет инициализация FirebaseMessaging
    // await Firebase.initializeApp();
    // FirebaseMessaging.instance.requestPermission();
    // String? token = await FirebaseMessaging.instance.getToken();
    
    debugPrint('🔔 [FCM STUB] NotificationService initialized. Waiting for real Firebase credentials.');
  }

  void handleIncomingMessages() {
    // В будущем:
    // FirebaseMessaging.onMessage.listen((RemoteMessage message) { ... });
    debugPrint('🔔 [FCM STUB] Listening for incoming messages.');
  }
}
