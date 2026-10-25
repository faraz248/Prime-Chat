class MessageModel {
  final String id;
  final String senderId;
  final String text;
  final DateTime timestamp;
  final bool isAiResponse;
  final String? imageUrl;
  final String? audioUrl;
  final String? videoUrl;

  final Map<String, String> reactions;
  final Map<String, dynamic>? replyTo;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.text,
    required this.timestamp,
    this.isAiResponse = false,
    this.imageUrl,
    this.audioUrl,
    this.videoUrl,
    this.reactions = const {},
    this.replyTo,
  });

  factory MessageModel.fromMap(Map<String, dynamic> data, String documentId) {
    Map<String, String> mappedReactions = {};
    if (data['reactions'] is Map) {
      (data['reactions'] as Map).forEach((k, v) {
        if (k != null && v != null) {
          mappedReactions[k.toString()] = v.toString();
        }
      });
    }

    return MessageModel(
      id: documentId,
      senderId: data['senderId'] ?? '',
      text: data['text'] ?? '',
      timestamp: (data['timestamp'] as dynamic)?.toDate() ?? DateTime.now(),
      isAiResponse: data['isAiResponse'] ?? false,
      imageUrl: data['imageUrl'],
      audioUrl: data['audioUrl'],
      videoUrl: data['videoUrl'],
      reactions: mappedReactions,
      replyTo: data['replyTo'] is Map ? Map<String, dynamic>.from(data['replyTo']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'text': text,
      'timestamp': timestamp,
      'isAiResponse': isAiResponse,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (audioUrl != null) 'audioUrl': audioUrl,
      if (videoUrl != null) 'videoUrl': videoUrl,
      if (reactions.isNotEmpty) 'reactions': reactions,
      if (replyTo != null) 'replyTo': replyTo,
    };
  }
}
