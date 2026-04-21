package com.example.backend.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Service
@Slf4j
public class NotificationService {

    public void sendPushNotification(Long userId, String title, String body) {
        // Заглушка для отправки Push-уведомлений через Firebase Cloud Messaging (FCM)
        // В будущем здесь будет интеграция с com.google.firebase.messaging.FirebaseMessaging
        log.info("🔔 [PUSH NOTIFICATION] To User ID: {} | Title: {} | Body: {}", userId, title, body);
    }
}
