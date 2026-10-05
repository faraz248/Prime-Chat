import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
    // ID parsing for styling
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
        title: Text(showOnlyDeleted ? 'Deleted in $roomName' : 'Spying: $roomName', style: const TextStyle(color: Colors.redAccent, fontSize: 16)),
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
            return const Center(child: Text("No messages yet.", style: TextStyle(color: Colors.white54)));
          }

          return ListView.builder(
            reverse: true,
            padding: const EdgeInsets.all(10),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index].data() as Map<String, dynamic>;
              final senderId = msg['senderId'] ?? '';
              final text = msg['text'] ?? '';
              
              String senderName = 'Unknown User';
              
              if (senderId == 'ai_assistant') {
                senderName = '🤖 AI Assistant';
              } else {
                senderName = userNames[senderId] ?? 'User ($senderId)';
              }

              // Styling Logic
              bool isUser1 = senderId == user1;
              bool isAi = senderId == 'ai_assistant';

              Color bubbleColor;
              Alignment alignment;
              Color nameColor;

              if (isAi) {
                bubbleColor = const Color(0xFFE94560).withOpacity(0.3); // Red tint for AI
                alignment = Alignment.center; // AI in middle
                nameColor = Colors.amber;
              } else if (isUser1) {
                bubbleColor = const Color(0xFF533483); // Purple for User 1
                alignment = Alignment.centerRight; // User 1 on Right
                nameColor = Colors.white;
              } else {
                bubbleColor = const Color(0xFF16213E); // Dark Blue for User 2
                alignment = Alignment.centerLeft; // User 2 on Left
                nameColor = Colors.cyanAccent;
              }

              return Align(
                alignment: alignment,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        senderName, 
                        style: TextStyle(color: nameColor, fontWeight: FontWeight.bold, fontSize: 11)
                      ),
                      const SizedBox(height: 4),
                      Text(
                        text, 
                        style: const TextStyle(color: Colors.white, fontSize: 15)
                      ),
                      if (msg['isDeleted'] == true) ...[
                        const SizedBox(height: 4),
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.delete_forever, size: 12, color: Colors.redAccent),
                            SizedBox(width: 4),
                            Text('Deleted by user', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ],
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
