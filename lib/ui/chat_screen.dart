import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/providers.dart';
import '../models/message_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/chat_service.dart';
import 'add_member_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String chatRoomId;
  final String? friendName;
  final bool isGroup;
  const ChatScreen({Key? key, required this.chatRoomId, this.friendName, this.isGroup = false}) : super(key: key);

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final Map<String, String> _userNamesCache = {};

  @override
  void initState() {
    super.initState();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUserId.isNotEmpty) {
      ChatService().markAsRead(widget.chatRoomId, currentUserId);
    }
    if (widget.isGroup) {
      _loadGroupMembers();
    }
  }

  Future<void> _loadGroupMembers() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('chatRooms').doc(widget.chatRoomId).get();
      final data = doc.data();
      if (data != null) {
        List<dynamic> members = data['members'] ?? [];
        for (var m in members) {
          if (!_userNamesCache.containsKey(m)) {
            final userDoc = await FirebaseFirestore.instance.collection('users').doc(m).get();
            if (userDoc.exists) {
              _userNamesCache[m] = userDoc.data()?['displayName'] ?? 'Unknown';
            }
          }
        }
        if (mounted) setState(() {});
      }
    } catch (e) {
      // fail silently
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    // In a real app, user ID comes from Auth. Using placeholder here if null.
    final currentUser = FirebaseAuth.instance.currentUser;
    final senderId = currentUser?.uid ?? 'user_123'; 

    ref.read(chatServiceProvider).sendMessage(widget.chatRoomId, senderId, text);
    _messageController.clear();
  }

  Future<void> _startVoiceCall() async {
    final roomName = "NEXUS_Call_${widget.chatRoomId}".replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final url = Uri.parse("https://meet.jit.si/$roomName#config.startWithVideoMuted=true");
    
    final currentUser = FirebaseAuth.instance.currentUser;
    final senderId = currentUser?.uid ?? 'user_123'; 
    ref.read(chatServiceProvider).sendMessage(widget.chatRoomId, senderId, "📞 I started a voice call. Click the phone icon above to join!");
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the call.')));
      }
    }
  }

  void _confirmClearChat(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Clear Chat', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to delete all messages in this chat?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(chatServiceProvider).clearChat(widget.chatRoomId);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteMessage(BuildContext context, String messageId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete Message', style: TextStyle(color: Colors.white)),
        content: const Text('Delete this message for everyone?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(chatServiceProvider).deleteMessage(widget.chatRoomId, messageId);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showGroupInfo(BuildContext context) async {
    showDialog(
      context: context, 
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.redAccent))
    );

    try {
      final doc = await FirebaseFirestore.instance.collection('chatRooms').doc(widget.chatRoomId).get();
      final data = doc.data() as Map<String, dynamic>?;
      List<dynamic> memberIds = data?['members'] ?? [];
      
      List<Map<String, dynamic>> memberDetails = [];
      for (var id in memberIds) {
        final uDoc = await FirebaseFirestore.instance.collection('users').doc(id.toString()).get();
        if (uDoc.exists) {
           final uData = uDoc.data() as Map<String, dynamic>;
           memberDetails.add({
             'name': uData['displayName'] ?? 'Unknown',
             'email': uData['email'] ?? '',
           });
        }
      }

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            title: Text('${widget.friendName} Members', style: const TextStyle(color: Colors.white)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: memberDetails.length,
                itemBuilder: (context, idx) {
                  return ListTile(
                    leading: const Icon(Icons.person, color: Colors.blueAccent),
                    title: Text(memberDetails[idx]['name'], style: const TextStyle(color: Colors.white)),
                    subtitle: Text(memberDetails[idx]['email'], style: const TextStyle(color: Colors.white54)),
                  );
                }
              ),
            ),
            actions: [
               TextButton(
                 onPressed: () {
                   Navigator.pop(context);
                   Navigator.push(context, MaterialPageRoute(builder: (_) => AddMemberScreen(chatRoomId: widget.chatRoomId)));
                 },
                 child: const Text('Add Member', style: TextStyle(color: Colors.blueAccent)),
               ),
               TextButton(
                 onPressed: () => Navigator.pop(context),
                 child: const Text('Close', style: TextStyle(color: Colors.redAccent)),
               )
            ]
          )
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading members: $e')));
      }
    }
  }

  String get _friendId {
    if (widget.isGroup) return '';
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final ids = widget.chatRoomId.split('_');
    if (ids.length == 2) {
      return ids[0] == currentUserId ? ids[1] : ids[0];
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(messagesProvider(widget.chatRoomId));
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUserId = currentUser?.uid ?? 'user_123';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.friendName ?? 'NEXUS', style: const TextStyle(fontSize: 18)),
            if (!widget.isGroup && _friendId.isNotEmpty)
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(_friendId).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
                  final data = snapshot.data!.data() as Map<String, dynamic>;
                  final Timestamp? lastSeen = data['lastSeen'];
                  if (lastSeen == null) return const SizedBox.shrink();
                  
                  final diff = DateTime.now().difference(lastSeen.toDate());
                  String status = '';
                  if (diff.inMinutes < 2) {
                    status = 'Online';
                  } else if (diff.inHours < 1) {
                    status = 'Last seen ${diff.inMinutes} mins ago';
                  } else if (diff.inDays < 1) {
                    status = 'Last seen ${diff.inHours} hours ago';
                  } else {
                    status = 'Last seen ${diff.inDays} days ago';
                  }
                  
                  return Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      color: status == 'Online' ? Colors.greenAccent : Colors.white70,
                      fontWeight: FontWeight.normal
                    ),
                  );
                },
              ),
          ],
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x88E94560),
                Color(0xFF0D0D12),
              ],
            ),
          ),
        ),
        actions: [
          if (widget.isGroup)
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Group Info',
              onPressed: () => _showGroupInfo(context),
            ),
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: 'Voice Call',
            onPressed: _startVoiceCall,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear Chat',
            onPressed: () => _confirmClearChat(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet. Type @AI to wake the assistant.',
                      style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe = message.senderId == currentUserId;
                    final isAi = message.isAiResponse || message.senderId == 'ai_assistant';

                    return GestureDetector(
                      onLongPress: () {
                        if (isMe) {
                          _confirmDeleteMessage(context, message.id);
                        }
                      },
                      child: _ChatBubble(
                        message: message,
                        isMe: isMe,
                        isAi: isAi,
                        isGroup: widget.isGroup,
                        senderName: _userNamesCache[message.senderId],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFE94560))),
              error: (e, st) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Type a message... (@AI for assistant)',
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFE94560), Color(0xFF533483)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: IconButton(
                icon: const Icon(Icons.send_rounded, color: Colors.white),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final bool isAi;
  final bool isGroup;
  final String? senderName;

  const _ChatBubble({
    Key? key,
    required this.message,
    required this.isMe,
    required this.isAi,
    this.isGroup = false,
    this.senderName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor = isMe 
        ? const Color(0xFF533483) 
        : isAi 
            ? const Color(0xFFE94560).withOpacity(0.8)
            : const Color(0xFF1E1E28);
    
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(isMe || isAi ? 20 : 0),
      bottomRight: Radius.circular(isMe ? 0 : 20),
    );

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: radius,
          boxShadow: [
            if (isAi)
              BoxShadow(
                color: const Color(0xFFE94560).withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 1,
              ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isAi) ...[
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: Colors.amberAccent),
                  SizedBox(width: 4),
                  Text(
                    'AI Assistant',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.amberAccent,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ] else if (isGroup && !isMe) ...[
              Text(
                '~ ${senderName ?? 'Unknown'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.amberAccent,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              message.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                DateFormat('dd MMM, HH:mm').format(message.timestamp),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
