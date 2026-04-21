class ChatMessage {
  final int id;
  final int chatRoomId;
  final int senderId;
  final String senderName;
  final String content;
  final bool isRead;
  final DateTime? timestamp;

  ChatMessage({
    required this.id,
    required this.chatRoomId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.isRead,
    this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      chatRoomId: (json['chatRoomId'] as num?)?.toInt() ?? 0,
      senderId: (json['senderId'] as num?)?.toInt() ?? 0,
      senderName: json['senderName']?.toString() ?? 'Пользователь',
      content: json['content']?.toString() ?? '',
      isRead: json['isRead'] as bool? ?? false,
      timestamp: json['timestamp'] != null ? DateTime.tryParse(json['timestamp'].toString()) : null,
    );
  }
}
