import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/gemini_service.dart';

class AdminChatView extends StatelessWidget {
  final String chatRoomId;
  final String roomName;
  final Map<String, String> userNames;
  final bool showOnlyDeleted;

  const AdminChatView({
    Key? key,
    required this.chatRoomId,
    required this.roomName,
    required this.userNames,
    this.showOnlyDeleted = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isAiRoom = chatRoomId.startsWith('ai_room_');
    String user1 = '';
    String user2 = '';
    
    if (isAiRoom) {
      user1 = chatRoomId.replaceAll('ai_room_', '');
    } else {
      final ids = chatRoomId.split('_');
      if (ids.length == 2) {
        user1 = ids[0];
        user2 = ids[1];
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              showOnlyDeleted ? 'Deleted Messages' : roomName, 
              style: const TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              isAiRoom ? 'AI Assistant Conversation Audit' : 'Chat Audit Mode (Admin)', 
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.redAccent),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chatRooms')
            .doc(chatRoomId)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
          
          final messages = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final isDeleted = data['isDeleted'] == true;
            return showOnlyDeleted ? isDeleted : true;
          }).toList();

          if (messages.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(showOnlyDeleted ? Icons.delete_outline : Icons.chat_bubble_outline, color: Colors.white24, size: 50),
                  const SizedBox(height: 10),
                  Text(
                    showOnlyDeleted ? "No deleted messages in this room." : "No messages found in this chat room.",
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index].data() as Map<String, dynamic>;
              final senderId = msg['senderId'] ?? '';
              final rawText = msg['text'] ?? '';
              final isDeleted = msg['isDeleted'] == true;
              final imageUrl = msg['imageUrl'] as String?;
              final audioUrl = msg['audioUrl'] as String?;
              final videoUrl = msg['videoUrl'] as String?;
              
              String senderName = 'Unknown User';
              if (senderId == 'ai_assistant') {
                senderName = '🤖 AI Assistant';
              } else {
                senderName = userNames[senderId] ?? 'User ($senderId)';
              }

              // Deleted metadata
              final deletedByName = msg['deletedByName'] ?? 
                  (msg['deletedBy'] != null ? userNames[msg['deletedBy']] : senderName);
              final delTs = msg['deletedAt'] as Timestamp?;
              final delTimeStr = delTs != null ? DateFormat('dd MMM, hh:mm a').format(delTs.toDate()) : '';

              final ts = msg['timestamp'] as Timestamp?;
              final timeStr = ts != null ? DateFormat('hh:mm a').format(ts.toDate()) : '';

              // Clean text if AI response
              final displayText = senderId == 'ai_assistant' 
                  ? GeminiService.cleanAiFormatting(rawText) 
                  : rawText;

              bool isUser1 = senderId == user1;
              bool isAi = senderId == 'ai_assistant';

              Color baseBubbleColor;
              Alignment alignment;
              Color nameColor;

              if (isAi) {
                baseBubbleColor = const Color(0xFFE94560);
                alignment = Alignment.center;
                nameColor = Colors.amberAccent;
              } else if (isUser1) {
                baseBubbleColor = const Color(0xFF533483);
                alignment = Alignment.centerRight;
                nameColor = Colors.white;
              } else {
                baseBubbleColor = const Color(0xFF16213E);
                alignment = Alignment.centerLeft;
                nameColor = Colors.cyanAccent;
              }

              // If deleted: render "thoda light" (low opacity, dimmed, translucent)
              final bubbleColor = isDeleted 
                  ? baseBubbleColor.withOpacity(0.20)
                  : isAi 
                      ? baseBubbleColor.withOpacity(0.35) 
                      : baseBubbleColor;

              final borderColor = isDeleted 
                  ? Colors.redAccent.withOpacity(0.55) 
                  : Colors.white12;

              final textColor = isDeleted 
                  ? Colors.white60 
                  : Colors.white;

              return Align(
                alignment: alignment,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor, width: isDeleted ? 1.4 : 1.0),
                    boxShadow: [
                      if (isDeleted)
                        BoxShadow(
                          color: Colors.redAccent.withOpacity(0.12),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Prominent DELETED Badge if message was deleted
                      if (isDeleted) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.delete_forever, size: 14, color: Colors.redAccent),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'DELETED by $deletedByName ${delTimeStr.isNotEmpty ? "• $delTimeStr" : ""}',
                                  style: const TextStyle(
                                    color: Colors.redAccent, 
                                    fontSize: 10, 
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Header with Sender Name and Time
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              senderName, 
                              style: TextStyle(
                                color: isDeleted ? nameColor.withOpacity(0.65) : nameColor, 
                                fontWeight: FontWeight.bold, 
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timeStr, 
                            style: TextStyle(color: isDeleted ? Colors.white30 : Colors.white54, fontSize: 10),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Media Thumbnails if present
                      if (imageUrl != null && imageUrl.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Opacity(
                            opacity: isDeleted ? 0.6 : 1.0,
                            child: Image.network(
                              imageUrl,
                              height: 140,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Text('[Image unavailable]', style: TextStyle(color: Colors.white54, fontSize: 11)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],

                      if (audioUrl != null && audioUrl.isNotEmpty) ...[
                        Row(
                          children: [
                            Icon(Icons.mic, color: isDeleted ? Colors.white38 : Colors.greenAccent, size: 16),
                            const SizedBox(width: 4),
                            Text('Voice Note', style: TextStyle(color: isDeleted ? Colors.white38 : Colors.white70, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],

                      if (videoUrl != null && videoUrl.isNotEmpty) ...[
                        Row(
                          children: [
                            Icon(Icons.videocam, color: isDeleted ? Colors.white38 : Colors.blueAccent, size: 16),
                            const SizedBox(width: 4),
                            Text('Video Message', style: TextStyle(color: isDeleted ? Colors.white38 : Colors.white70, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],

                      // Message Content Text
                      if (displayText.isNotEmpty && 
                          displayText != "📷 Image" && 
                          displayText != "📷 Photo" && 
                          displayText != "🎥 Video" && 
                          displayText != "🎤 Audio Note")
                        Text(
                          displayText, 
                          style: TextStyle(
                            color: textColor, 
                            fontSize: 14,
                            height: 1.35,
                            fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
