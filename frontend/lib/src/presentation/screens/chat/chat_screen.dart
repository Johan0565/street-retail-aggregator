import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../../../domain/chat_message.dart';
import '../../../domain/chat_room.dart';
import '../../../services/chat_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ChatScreen extends StatefulWidget {
  final int applicationId;
  final String applicationTitle;

  const ChatScreen({
    super.key,
    required this.applicationId,
    required this.applicationTitle,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  ChatRoom? _chatRoom;
  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  int _currentUserId = 0;

  @override
  void initState() {
    super.initState();
    _loadUserAndRoom();
  }

  Future<void> _loadUserAndRoom() async {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'jwt_token');
    if (token != null) {
      try {
        final decodedToken = JwtDecoder.decode(token);
        // Sometimes id is stored as string or int depending on backend
        setState(() {
           final idRaw = decodedToken['userId'] ?? decodedToken['id'];
           if (idRaw != null) {
             _currentUserId = int.tryParse(idRaw.toString()) ?? 0;
           }
        });
      } catch (e) {
        debugPrint('Token decode error: $e');
      }
    }

    try {
      final room = await _chatService.getOrCreateRoom(widget.applicationId);
      setState(() {
        _chatRoom = room;
      });
      
      final messages = await _chatService.getMessages(room.id);
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
      
      _scrollToBottom();
      
      _chatService.connectStomp(room.id, (message) {
        setState(() {
          if (!_messages.any((m) => m.id == message.id)) {
            _messages.add(message);
            _scrollToBottom();
          }
        });
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки чата: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _chatRoom == null) return;

    _messageController.clear();
    
    try {
      final message = await _chatService.sendMessage(_chatRoom!.id, text);
      setState(() {
        if (!_messages.any((m) => m.id == message.id)) {
          _messages.add(message);
        }
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _chatService.disconnectStomp();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Чат: ${widget.applicationTitle}'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF8C00)))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      // Fallback: if _currentUserId is 0, we can guess by matching senderId with landlord/tenant
                      // but for now, rely on _currentUserId matching.
                      // If it's 0, all messages might appear on the left, but we assume auth works.
                      bool isMe = message.senderId == _currentUserId;
                      if (_currentUserId == 0 && _chatRoom != null) {
                         // fallback guess
                         isMe = message.senderId == _chatRoom!.tenantId; // assuming we are tenant
                      }
                      return _buildMessageBubble(message, isMe);
                    },
                  ),
                ),
                _buildMessageInput(),
              ],
            ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMe) {
    final timeStr = message.timestamp != null 
        ? DateFormat('HH:mm').format(message.timestamp!.toLocal()) 
        : '';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFFFF8C00) : Colors.grey[200],
            borderRadius: BorderRadius.circular(16).copyWith(
              bottomRight: isMe ? const Radius.circular(0) : null,
              bottomLeft: !isMe ? const Radius.circular(0) : null,
            ),
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Text(
                  message.senderName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                message.content,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                timeStr,
                style: TextStyle(
                  color: isMe ? Colors.white70 : Colors.black54,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, -2),
            blurRadius: 10,
          )
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Написать сообщение...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendMessage,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Color(0xFFFF8C00),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
