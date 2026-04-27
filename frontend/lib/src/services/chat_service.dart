import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../domain/chat_message.dart';
import '../domain/chat_room.dart';

class ChatService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'http://10.0.2.2:8080',
    headers: {'Content-Type': 'application/json'},
  ));
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  StompClient? _stompClient;

  Future<ChatRoom> getOrCreateRoom(int applicationId) async {
    final token = await _storage.read(key: 'jwt_token');
    final response = await _dio.get(
      '/api/chat/applications/$applicationId/room',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return ChatRoom.fromJson(response.data);
  }

  Future<List<ChatMessage>> getMessages(int roomId) async {
    final token = await _storage.read(key: 'jwt_token');
    final response = await _dio.get(
      '/api/chat/rooms/$roomId/messages',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return (response.data as List).map((e) => ChatMessage.fromJson(e)).toList();
  }

  Future<ChatMessage> sendMessage(int roomId, String content) async {
    final token = await _storage.read(key: 'jwt_token');
    final response = await _dio.post(
      '/api/chat/rooms/$roomId/messages',
      data: {'content': content},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return ChatMessage.fromJson(response.data);
  }

  void connectStomp(int roomId, Function(ChatMessage) onMessageReceived) async {
    final token = await _storage.read(key: 'jwt_token');
    
    _stompClient = StompClient(
      config: StompConfig(
        url: 'ws://10.0.2.2:8080/ws/websocket',
        onConnect: (StompFrame frame) {
          _stompClient?.subscribe(
            destination: '/topic/chat/$roomId',
            callback: (frame) {
              if (frame.body != null) {
                final json = jsonDecode(frame.body!);
                final message = ChatMessage.fromJson(json);
                onMessageReceived(message);
              }
            },
          );
        },
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
      ),
    );

    _stompClient?.activate();
  }

  void disconnectStomp() {
    _stompClient?.deactivate();
    _stompClient = null;
  }
}
