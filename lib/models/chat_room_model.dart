class ChatRoomModel {
  final String id;
  final List<String> participants; // User IDs
  final DateTime lastMessageTime;
  final String lastMessage;

  ChatRoomModel({
    required this.id,
    required this.participants,
    required this.lastMessageTime,
    required this.lastMessage,
  });

  factory ChatRoomModel.fromMap(Map<String, dynamic> data, String documentId) {
    return ChatRoomModel(
      id: documentId,
      participants: List<String>.from(data['participants'] ?? []),
      lastMessageTime: (data['lastMessageTime'] as dynamic)?.toDate() ?? DateTime.now(),
      lastMessage: data['lastMessage'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'participants': participants,
      'lastMessageTime': lastMessageTime,
      'lastMessage': lastMessage,
    };
  }
}
