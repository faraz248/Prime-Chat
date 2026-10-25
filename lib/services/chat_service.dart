import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
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
      'unreadCount_$userId': 0,
    }, SetOptions(merge: true));
  }

  Future<void> toggleReaction(String chatRoomId, String messageId, String userId, String emoji) async {
    final docRef = _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .doc(messageId);

    final doc = await docRef.get();
    if (!doc.exists) return;

    Map<String, dynamic> reactions = Map<String, dynamic>.from(doc.data()?['reactions'] ?? {});
    if (reactions[userId] == emoji) {
      reactions.remove(userId);
    } else {
      reactions[userId] = emoji;
    }

    await docRef.update({'reactions': reactions});
  }

  Future<String> _fetchInstantPhoto(String query) async {
    try {
      final wikiUrl = Uri.parse(
        'https://en.wikipedia.org/w/api.php?action=query&generator=search&gsrsearch=${Uri.encodeComponent(query)}&gsrlimit=1&prop=pageimages&piprop=original&format=json'
      );
      final res = await http.get(wikiUrl).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final pages = data['query']?['pages'] as Map<String, dynamic>?;
        if (pages != null && pages.isNotEmpty) {
          for (var p in pages.values) {
            final src = p['original']?['source'] as String?;
            if (src != null && src.isNotEmpty) {
              return src;
            }
          }
        }
      }
    } catch (_) {}

    // Fallback: Pollinations AI with encoded query
    return 'https://image.pollinations.ai/prompt/${Uri.encodeComponent(query)}?width=800&height=800&nologo=true';
  }

  Future<void> sendMessage(
    String chatRoomId, 
    String senderId, 
    String text, {
    String? imageUrl, 
    String? audioUrl, 
    String? videoUrl,
    Map<String, dynamic>? replyTo,
  }) async {
    // Determine receiverId to mark their chat as unread
    List<String> receiverIds = [];
    bool isGroup = false;
    
    final roomDoc = await _firestore.collection('chatRooms').doc(chatRoomId).get();
    if (roomDoc.exists) {
      final roomData = roomDoc.data() as Map<String, dynamic>;
      if (roomData['members'] is List) {
        final List members = roomData['members'];
        for (var m in members) {
          final mStr = m.toString();
          if (mStr != senderId && mStr.isNotEmpty) {
            receiverIds.add(mStr);
          }
        }
      }
      if (roomData['isGroup'] == true) {
        isGroup = true;
      }
    }

    if (receiverIds.isEmpty) {
      if (chatRoomId.startsWith('ai_room_')) {
        final uid = chatRoomId.replaceAll('ai_room_', '');
        if (senderId != 'ai_assistant') receiverIds.add('ai_assistant');
        if (senderId != uid) receiverIds.add(uid);
      } else {
        final parts = chatRoomId.split('_');
        for (var p in parts) {
          if (p != senderId && p.isNotEmpty) {
            receiverIds.add(p);
          }
        }
      }
    }

    // 1. Save user's message
    final messageData = {
      'senderId': senderId,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'isAiResponse': false,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (audioUrl != null) 'audioUrl': audioUrl,
      if (videoUrl != null) 'videoUrl': videoUrl,
      if (replyTo != null) 'replyTo': replyTo,
      'reactions': {},
    };
    
    await _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .add(messageData);

    // Human-readable snippet for chat preview
    final previewSnippet = imageUrl != null
        ? '📷 Photo'
        : videoUrl != null
            ? '🎥 Video'
            : audioUrl != null
                ? '🎤 Audio Note'
                : text;

    // Update last message in chat room and set unread flag & increment counter
    Map<String, dynamic> updateData = {
      'lastMessage': previewSnippet,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': senderId,
    };

    if (!isGroup && !chatRoomId.startsWith('ai_room_')) {
      final parts = chatRoomId.split('_');
      if (parts.length >= 2) {
        updateData['members'] = FieldValue.arrayUnion([senderId, ...receiverIds]);
        updateData['isGroup'] = false;
      }
    }

    for (var rId in receiverIds) {
      if (rId.isNotEmpty) {
        updateData['hasUnread_$rId'] = true;
        updateData['unreadCount_$rId'] = FieldValue.increment(1);
      }
    }
    // Sender has 0 unread in their own room
    updateData['hasUnread_$senderId'] = false;
    updateData['unreadCount_$senderId'] = 0;

    await _firestore.collection('chatRooms').doc(chatRoomId).set(updateData, SetOptions(merge: true));

    // 2. Trigger Gemini response
    final lowerText = text.toLowerCase();
    final isAiRoom = chatRoomId.startsWith('ai_room_');
    final hasAiCommand = lowerText.startsWith('@ai');
    
    // AI tabhi reply karega jab ya toh 'AI Assistant' room ho, ya kisi ne message me @ai likha ho
    if (isAiRoom || hasAiCommand) {
      
      String prompt = text;
      if (hasAiCommand) {
        prompt = text.substring(3).trim();
      }
      
      if (prompt.isNotEmpty) {
        String aiResponse = await _geminiService.getAiResponse(prompt);
        String? generatedImageUrl;

        // Check if response contains [IMAGE: ...] tag
        final imageTagRegex = RegExp(r'\[IMAGE:\s*([^\]]+)\]', caseSensitive: false);
        final match = imageTagRegex.firstMatch(aiResponse);
        if (match != null) {
          final visualPrompt = match.group(1)?.trim() ?? '';
          if (visualPrompt.isNotEmpty) {
            generatedImageUrl = await _fetchInstantPhoto(visualPrompt);
          }
          // Remove the tag from the displayed text
          aiResponse = aiResponse.replaceAll(imageTagRegex, '').trim();
        } else {
          // Fallback: If user asked for photo/image/tasveer, but Gemini didn't include the tag
          final hasImageIntent = RegExp(r'(photo|tasveer|tasvir|image|pic|picture|wallpaper)', caseSensitive: false).hasMatch(prompt);
          if (hasImageIntent) {
            String cleanQuery = prompt
                .replaceAll(RegExp(r'(photo|tasveer|tasvir|image|pic|picture|wallpaper|bhejo|send|kro|kar do|dikhao|chahiye|de do|please|mujhe|tum|ek|ki|ka)', caseSensitive: false), ' ')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
            if (cleanQuery.isEmpty) cleanQuery = 'cute puppy dog';
            generatedImageUrl = await _fetchInstantPhoto(cleanQuery);
          }
        }

        if (aiResponse.isEmpty) {
          aiResponse = 'Here is the photo you requested! 🎨';
        }
        
        // Save AI response
        final aiMessageData = {
          'senderId': 'ai_assistant',
          'text': aiResponse,
          'timestamp': FieldValue.serverTimestamp(),
          'isAiResponse': true,
          if (generatedImageUrl != null) 'imageUrl': generatedImageUrl,
          'reactions': {},
        };
        
        await _firestore
            .collection('chatRooms')
            .doc(chatRoomId)
            .collection('messages')
            .add(aiMessageData);
            
        // AI replied, so mark it unread for the original sender
        await _firestore.collection('chatRooms').doc(chatRoomId).set({
          'lastMessage': generatedImageUrl != null ? '📷 $aiResponse' : aiResponse,
          'lastMessageTime': FieldValue.serverTimestamp(),
          'hasUnread_$senderId': true,
          'unreadCount_$senderId': FieldValue.increment(1),
        }, SetOptions(merge: true));
      }
    }
  }

  Future<void> clearChat(String chatRoomId) async {
    final messages = await _firestore.collection('chatRooms').doc(chatRoomId).collection('messages').get();
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
