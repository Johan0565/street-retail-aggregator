class ChatRoom {
  final int id;
  final int applicationId;
  final int landlordId;
  final String landlordName;
  final int tenantId;
  final String tenantName;

  ChatRoom({
    required this.id,
    required this.applicationId,
    required this.landlordId,
    required this.landlordName,
    required this.tenantId,
    required this.tenantName,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: (json['id'] as num?)?.toInt() ?? 0,
      applicationId: (json['applicationId'] as num?)?.toInt() ?? 0,
      landlordId: (json['landlordId'] as num?)?.toInt() ?? 0,
      landlordName: json['landlordName']?.toString() ?? 'Владелец',
      tenantId: (json['tenantId'] as num?)?.toInt() ?? 0,
      tenantName: json['tenantName']?.toString() ?? 'Арендатор',
    );
  }
}
