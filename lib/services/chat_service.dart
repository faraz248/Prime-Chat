import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message_model.dart';
import 'gemini_service.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GeminiService _geminiService = GeminiService();

  Stream<List<MessageModel>> getMessages(String chatRoomId) {
    return _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .where((doc) {
            final data = doc.data();
            return data['isDeleted'] != true;
          })
          .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  Future<void> markAsRead(String chatRoomId, String userId) async {
    await _firestore.collection('chatRooms').doc(chatRoomId).set({
      'hasUnread_$userId': false,
    }, SetOptions(merge: true));
  }

  Future<void> sendMessage(String chatRoomId, String senderId, String text) async {
    // Determine receiverId to mark their chat as unread
    List<String> receiverIds = [];
    bool isGroup = false;
    
    // Check if it's a group
    final roomDoc = await _firestore.collection('chatRooms').doc(chatRoomId).get();
    if (roomDoc.exists) {
      final roomData = roomDoc.data() as Map<String, dynamic>;
      if (roomData['isGroup'] == true) {
        isGroup = true;
        List<dynamic> members = roomData['members'] ?? [];
        for (var m in members) {
          if (m != senderId) receiverIds.add(m.toString());
        }
      }
    }

    if (!isGroup) {
      if (chatRoomId.startsWith('ai_room_')) {
        final uid = chatRoomId.replaceAll('ai_room_', '');
        receiverIds.add(senderId == uid ? 'ai_assistant' : uid);
      } else {
        final ids = chatRoomId.split('_');
        if (ids.length == 2) {
          receiverIds.add(ids[0] == senderId ? ids[1] : ids[0]);
        }
      }
    }

    // 1. Save user's message
    final messageData = {
      'senderId': senderId,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'isAiResponse': false,
    };
    
    await _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .add(messageData);

    // Update last message in chat room and set unread flag for receivers
    Map<String, dynamic> updateData = {
      'lastMessage': text,
      'lastMessageTime': FieldValue.serverTimestamp(),
    };
    for (var rId in receiverIds) {
      if (rId.isNotEmpty) {
        updateData['hasUnread_$rId'] = true;
      }
    }
    await _firestore.collection('chatRooms').doc(chatRoomId).set(updateData, SetOptions(merge: true));

    // 2. Trigger Gemini response
    final lowerText = text.toLowerCase();
    final isAiRoom = chatRoomId.startsWith('ai_room_');
    final hasAiCommand = lowerText.startsWith('@ai');
    
    // AI tabhi reply karega jab ya toh 'AI Assistant' room ho, ya kisi ne message me @ai likha ho
    if (isAiRoom || hasAiCommand) {
      
      String prompt = text;
      // Agar @ai likha hai, toh usko remove kar do prompt se pehle
      if (hasAiCommand) {
        prompt = text.substring(3).trim();
      }
      
      if (prompt.isNotEmpty) {
        final aiResponse = await _geminiService.getAiResponse(prompt);
        
        // Save AI response
        final aiMessageData = {
          'senderId': 'ai_assistant',
          'text': aiResponse,
          'timestamp': FieldValue.serverTimestamp(),
          'isAiResponse': true,
        };
        
        await _firestore
            .collection('chatRooms')
            .doc(chatRoomId)
            .collection('messages')
            .add(aiMessageData);
            
        // AI replied, so mark it unread for the original sender
        await _firestore.collection('chatRooms').doc(chatRoomId).set({
          'lastMessage': aiResponse,
          'lastMessageTime': FieldValue.serverTimestamp(),
          'hasUnread_$senderId': true,
        }, SetOptions(merge: true));
      }
    }
  }

  Future<void> clearChat(String chatRoomId) async {
    final messages = await _firestore.collection('chatRooms').doc(chatRoomId).collection('messages').get();
    // Use a batch to delete messages
    WriteBatch batch = _firestore.batch();
    for (var doc in messages.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    await _firestore.collection('chatRooms').doc(chatRoomId).set({
      'lastMessage': '',
    }, SetOptions(merge: true));
  }

  Future<void> deleteMessage(String chatRoomId, String messageId) async {
    await _firestore.collection('chatRooms').doc(chatRoomId).collection('messages').doc(messageId).delete();
  }
}
