import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../providers/providers.dart';
import '../models/message_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/chat_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../utils/file_saver.dart';
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
  final FocusNode _inputFocusNode = FocusNode();
  final Map<String, String> _userNamesCache = {};
  bool _isUploadingImage = false;
  bool _isUploadingVideo = false;
  
  // Swipe to reply state
  MessageModel? _replyingToMessage;

  final _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isUploadingAudio = false;
  Timer? _recordTimer;
  int _recordDuration = 0;

  @override
  void dispose() {
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    _messageController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

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
    } catch (_) {}
  }

  String _getSenderDisplayName(MessageModel msg) {
    if (msg.isAiResponse || msg.senderId == 'ai_assistant') return 'AI Assistant';
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (msg.senderId == currentUid) return 'You';
    if (_userNamesCache.containsKey(msg.senderId)) {
      return _userNamesCache[msg.senderId]!;
    }
    return widget.friendName ?? 'User';
  }

  void _setReplyTo(MessageModel message) {
    HapticFeedback.lightImpact();
    setState(() {
      _replyingToMessage = message;
    });
    _inputFocusNode.requestFocus();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    final senderId = currentUser?.uid ?? 'user_123';

    Map<String, dynamic>? replyToData;
    if (_replyingToMessage != null) {
      replyToData = {
        'messageId': _replyingToMessage!.id,
        'senderName': _getSenderDisplayName(_replyingToMessage!),
        'text': _replyingToMessage!.imageUrl != null
            ? '📷 Photo'
            : _replyingToMessage!.videoUrl != null
                ? '🎥 Video'
                : _replyingToMessage!.audioUrl != null
                    ? '🎤 Audio Note'
                    : _replyingToMessage!.text,
        if (_replyingToMessage!.imageUrl != null) 'imageUrl': _replyingToMessage!.imageUrl,
      };
    }

    ref.read(chatServiceProvider).sendMessage(
      widget.chatRoomId,
      senderId,
      text,
      replyTo: replyToData,
    );

    _messageController.clear();
    if (_replyingToMessage != null) {
      setState(() => _replyingToMessage = null);
    }
  }

  Future<void> _sendImage({ImageSource source = ImageSource.gallery}) async {
    final picker = ImagePicker();
    XFile? image;
    try {
      image = await picker.pickImage(source: source, imageQuality: 75, maxWidth: 1024, maxHeight: 1024);
    } catch (e) {
      if (source == ImageSource.camera) {
        try {
          image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1024, maxHeight: 1024);
        } catch (_) {}
      }
    }

    if (image == null) return;

    setState(() => _isUploadingImage = true);

    try {
      final Uint8List imageBytes = await image.readAsBytes();
      String? downloadUrl;

      // On Web, use instant Base64 (<30ms) to bypass Storage CORS delays
      if (kIsWeb) {
        final b64 = base64Encode(imageBytes);
        downloadUrl = 'data:image/jpeg;base64,$b64';
      } else {
        try {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('chat_images')
              .child(widget.chatRoomId)
              .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

          await storageRef.putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'))
              .timeout(const Duration(seconds: 4));
          downloadUrl = await storageRef.getDownloadURL().timeout(const Duration(seconds: 4));
        } catch (_) {
          final b64 = base64Encode(imageBytes);
          downloadUrl = 'data:image/jpeg;base64,$b64';
        }
      }

      if (downloadUrl != null) {
        final currentUser = FirebaseAuth.instance.currentUser;
        final senderId = currentUser?.uid ?? 'user_123';

        Map<String, dynamic>? replyToData;
        if (_replyingToMessage != null) {
          replyToData = {
            'messageId': _replyingToMessage!.id,
            'senderName': _getSenderDisplayName(_replyingToMessage!),
            'text': _replyingToMessage!.imageUrl != null
                ? '📷 Photo'
                : _replyingToMessage!.videoUrl != null
                    ? '🎥 Video'
                    : _replyingToMessage!.audioUrl != null
                        ? '🎤 Audio Note'
                        : _replyingToMessage!.text,
            if (_replyingToMessage!.imageUrl != null) 'imageUrl': _replyingToMessage!.imageUrl,
          };
        }

        await ref.read(chatServiceProvider).sendMessage(
          widget.chatRoomId,
          senderId,
          "📷 Photo",
          imageUrl: downloadUrl,
          replyTo: replyToData,
        );

        if (_replyingToMessage != null) {
          setState(() => _replyingToMessage = null);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to process image.')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error sending photo: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _sendVideo({ImageSource source = ImageSource.gallery}) async {
    final picker = ImagePicker();
    XFile? video;
    try {
      video = await picker.pickVideo(source: source);
    } catch (e) {
      if (source == ImageSource.camera) {
        try {
          video = await picker.pickVideo(source: ImageSource.gallery);
        } catch (_) {}
      }
    }

    if (video == null) return;

    setState(() => _isUploadingVideo = true);

    try {
      final Uint8List videoBytes = await video.readAsBytes();
      String? downloadUrl;

      if (kIsWeb && videoBytes.lengthInBytes < 950 * 1024) {
        final b64 = base64Encode(videoBytes);
        downloadUrl = 'data:video/mp4;base64,$b64';
      } else {
        try {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('chat_videos')
              .child(widget.chatRoomId)
              .child('${DateTime.now().millisecondsSinceEpoch}.mp4');

          await storageRef.putData(videoBytes, SettableMetadata(contentType: 'video/mp4'))
              .timeout(const Duration(seconds: 12));
          downloadUrl = await storageRef.getDownloadURL().timeout(const Duration(seconds: 5));
        } catch (storageErr) {
          if (videoBytes.lengthInBytes < 950 * 1024) {
            final b64 = base64Encode(videoBytes);
            downloadUrl = 'data:video/mp4;base64,$b64';
          }
        }
      }

      if (downloadUrl != null) {
        final currentUser = FirebaseAuth.instance.currentUser;
        final senderId = currentUser?.uid ?? 'user_123';
        await ref.read(chatServiceProvider).sendMessage(widget.chatRoomId, senderId, "🎥 Video", videoUrl: downloadUrl);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video upload timed out. Try a shorter video clip.')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error sending video: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploadingVideo = false);
    }
  }

  void _showAttachmentMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAttachmentOption(
                  icon: Icons.photo_library_rounded,
                  color: Colors.purpleAccent,
                  label: 'Gallery',
                  onTap: () {
                    Navigator.pop(ctx);
                    _sendImage(source: ImageSource.gallery);
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.camera_alt_rounded,
                  color: const Color(0xFFE94560),
                  label: 'Camera',
                  onTap: () {
                    Navigator.pop(ctx);
                    _sendImage(source: ImageSource.camera);
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.videocam_rounded,
                  color: Colors.blueAccent,
                  label: 'Video',
                  onTap: () {
                    Navigator.pop(ctx);
                    _sendVideo(source: ImageSource.gallery);
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.mic_rounded,
                  color: Colors.amberAccent,
                  label: 'Audio Note',
                  onTap: () {
                    Navigator.pop(ctx);
                    if (!_isRecording) {
                      _startRecording();
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.2),
              border: Border.all(color: color.withOpacity(0.6), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _startRecording() async {
    try {
      final hasPerm = await _audioRecorder.hasPermission();
      if (!hasPerm) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission is required to record audio notes.')),
          );
        }
        return;
      }

      String? path;
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }

      final config = RecordConfig(
        encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      );

      await _audioRecorder.start(config, path: path ?? '');
      _recordDuration = 0;
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) setState(() => _recordDuration++);
      });

      setState(() => _isRecording = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting voice recording: $e')),
        );
      }
    }
  }

  Future<void> _stopRecordingAndSend() async {
    _recordTimer?.cancel();
    try {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);

      if (path != null && path.isNotEmpty) {
        setState(() => _isUploadingAudio = true);

        Uint8List bytes;
        if (kIsWeb && path.startsWith('blob:')) {
          final res = await http.get(Uri.parse(path));
          bytes = res.bodyBytes;
        } else {
          final xfile = XFile(path);
          bytes = await xfile.readAsBytes();
        }

        if (bytes.isEmpty) {
          if (mounted) setState(() => _isUploadingAudio = false);
          return;
        }

        String? downloadUrl;
        final ext = kIsWeb ? 'opus' : 'm4a';
        final mimeType = kIsWeb ? 'audio/ogg' : 'audio/mp4';

        if (kIsWeb) {
          final b64 = base64Encode(bytes);
          downloadUrl = 'data:$mimeType;base64,$b64';
        } else {
          try {
            final storageRef = FirebaseStorage.instance
                .ref()
                .child('chat_audios')
                .child(widget.chatRoomId)
                .child('${DateTime.now().millisecondsSinceEpoch}.$ext');

            await storageRef.putData(bytes, SettableMetadata(contentType: mimeType))
                .timeout(const Duration(seconds: 5));
            downloadUrl = await storageRef.getDownloadURL().timeout(const Duration(seconds: 5));
          } catch (_) {
            final b64 = base64Encode(bytes);
            downloadUrl = 'data:$mimeType;base64,$b64';
          }
        }

        if (downloadUrl != null) {
          final currentUser = FirebaseAuth.instance.currentUser;
          final senderId = currentUser?.uid ?? 'user_123';
          await ref.read(chatServiceProvider).sendMessage(
            widget.chatRoomId, 
            senderId, 
            "🎤 Audio Note", 
            audioUrl: downloadUrl,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending audio note: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingAudio = false;
          _recordDuration = 0;
        });
      }
    }
  }

  Future<void> _startCall({required bool isVideo}) async {
    final cleanId = widget.chatRoomId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final roomName = "NEXUS_${isVideo ? 'Video' : 'Voice'}_$cleanId";
    // Crucial: configure audio un-muted and bypass prejoin screen so mic transmits immediately
    final url = Uri.parse(
      "https://meet.jit.si/$roomName#config.startWithAudioMuted=false&config.prejoinPageEnabled=false&config.startWithVideoMuted=${isVideo ? 'false' : 'true'}"
    );

    final currentUser = FirebaseAuth.instance.currentUser;
    final senderId = currentUser?.uid ?? 'user_123';
    await ref.read(chatServiceProvider).sendMessage(
      widget.chatRoomId, 
      senderId, 
      isVideo ? "📹 Video Call Started! Tap below to join." : "📞 Voice Call Started! Tap below to join.",
    );

    try {
      if (kIsWeb) {
        await launchUrl(url, webOnlyWindowName: '_blank');
      } else {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the call: $e')),
        );
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

  void _showMessageOptions(BuildContext context, MessageModel message, bool isMe) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    const emojis = ['❤️', '👍', '😂', '😮', '😢', '🙏', '🔥', '🎉'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Emoji Quick Reaction Bar
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0C20),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: emojis.map((emoji) {
                  final isReacted = message.reactions[currentUserId] == emoji;
                  return InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      ref.read(chatServiceProvider).toggleReaction(
                        widget.chatRoomId,
                        message.id,
                        currentUserId,
                        emoji,
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isReacted ? const Color(0xFFE94560).withOpacity(0.3) : Colors.transparent,
                        shape: BoxShape.circle,
                        border: isReacted ? Border.all(color: const Color(0xFFE94560), width: 1.5) : null,
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 24)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            // Actions
            ListTile(
              leading: const Icon(Icons.reply_rounded, color: Colors.blueAccent),
              title: const Text('Reply', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _setReplyTo(message);
              },
            ),
            if (message.text.isNotEmpty && !message.text.startsWith('📷') && !message.text.startsWith('🎥') && !message.text.startsWith('🎤'))
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: Colors.amberAccent),
                title: const Text('Copy Text', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: message.text));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message copied to clipboard!'), duration: Duration(seconds: 1)),
                  );
                },
              ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete for Everyone', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(chatServiceProvider).deleteMessage(widget.chatRoomId, message.id);
                },
              ),
          ],
        ),
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
            icon: const Icon(Icons.call_rounded),
            tooltip: 'Voice Call',
            onPressed: () => _startCall(isVideo: false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam_rounded),
            tooltip: 'Video Call',
            onPressed: () => _startCall(isVideo: true),
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

                    return Dismissible(
                      key: ValueKey('msg_${message.id}'),
                      direction: DismissDirection.startToEnd,
                      confirmDismiss: (direction) async {
                        _setReplyTo(message);
                        return false;
                      },
                      background: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE94560).withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.reply_rounded, color: Color(0xFFE94560), size: 24),
                        ),
                      ),
                      child: GestureDetector(
                        onLongPress: () => _showMessageOptions(context, message, isMe),
                        child: _ChatBubble(
                          message: message,
                          isMe: isMe,
                          isAi: isAi,
                          isGroup: widget.isGroup,
                          senderName: _userNamesCache[message.senderId],
                          chatRoomId: widget.chatRoomId,
                          currentUserId: currentUserId,
                          onReply: () => _setReplyTo(message),
                          onReactionToggle: (emoji) {
                            ref.read(chatServiceProvider).toggleReaction(
                              widget.chatRoomId,
                              message.id,
                              currentUserId,
                              emoji,
                            );
                          },
                        ),
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

  Widget _buildReplyPreview() {
    if (_replyingToMessage == null) return const SizedBox.shrink();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final senderName = _replyingToMessage!.senderId == currentUserId
        ? 'You'
        : _getSenderDisplayName(_replyingToMessage!);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E28),
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: Color(0xFFE94560), width: 4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, color: Color(0xFFE94560), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to $senderName',
                  style: const TextStyle(
                    color: Color(0xFFE94560),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _replyingToMessage!.imageUrl != null
                      ? '📷 Photo'
                      : _replyingToMessage!.videoUrl != null
                          ? '🎥 Video'
                          : _replyingToMessage!.audioUrl != null
                              ? '🎤 Audio Note'
                              : _replyingToMessage!.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() => _replyingToMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildReplyPreview(),
            if (_isUploadingImage || _isUploadingVideo || _isUploadingAudio)
              Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE94560)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isUploadingVideo
                          ? 'Sending video...'
                          : _isUploadingImage
                              ? 'Sending photo...'
                              : 'Sending audio note...',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            _isRecording
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          '00:${_recordDuration.toString().padLeft(2, '0')}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Recording audio note...',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.white70, size: 22),
                          tooltip: 'Discard',
                          onPressed: () async {
                            _recordTimer?.cancel();
                            await _audioRecorder.stop();
                            if (mounted) {
                              setState(() {
                                _isRecording = false;
                                _recordDuration = 0;
                              });
                            }
                          },
                        ),
                        Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFE94560),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                            tooltip: 'Send Audio Note',
                            onPressed: _isUploadingAudio ? null : _stopRecordingAndSend,
                          ),
                        ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      // Attachment Paperclip
                      IconButton(
                        icon: const Icon(Icons.attach_file_rounded, color: Colors.white70),
                        tooltip: 'Share Media',
                        onPressed: () => _showAttachmentMenu(context),
                      ),
                      // Camera Quick Snap Icon
                      IconButton(
                        icon: const Icon(Icons.camera_alt_rounded, color: Colors.white70),
                        tooltip: 'Take Photo',
                        onPressed: _isUploadingImage ? null : () => _sendImage(source: ImageSource.camera),
                      ),
                      // Input TextField Container
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F0C20),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: TextField(
                            controller: _messageController,
                            focusNode: _inputFocusNode,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Message... (@AI for assistant)',
                              hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                              border: InputBorder.none,
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Mic or Send Action
                      _messageController.text.trim().isNotEmpty
                          ? Container(
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
                            )
                          : Container(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF1E1E28),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.mic_rounded, color: Colors.white70),
                                tooltip: 'Tap to Record Voice Note',
                                onPressed: _isUploadingAudio ? null : _startRecording,
                              ),
                            ),
                    ],
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
  final String chatRoomId;
  final String currentUserId;
  final VoidCallback onReply;
  final Function(String emoji) onReactionToggle;

  const _ChatBubble({
    Key? key,
    required this.message,
    required this.isMe,
    required this.isAi,
    this.isGroup = false,
    this.senderName,
    required this.chatRoomId,
    required this.currentUserId,
    required this.onReply,
    required this.onReactionToggle,
  }) : super(key: key);

  Widget _buildImageWidget(String url, {double? height, double? width, BoxFit fit = BoxFit.cover}) {
    if (url.startsWith('data:image')) {
      final b64 = url.contains(',') ? url.split(',').last : url;
      final bytes = base64Decode(b64);
      return Image.memory(
        bytes,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 50),
      );
    }
    return Image.network(
      url,
      height: height,
      width: width,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          height: height ?? 200,
          width: width ?? double.infinity,
          color: Colors.black26,
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE94560)),
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 50),
    );
  }

  void _openFullImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _FullScreenImageViewer(imageUrl: imageUrl),
      ),
    );
  }

  Widget _buildCallCard(BuildContext context, {required bool isVideo}) {
    final cleanId = chatRoomId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final roomName = "NEXUS_${isVideo ? 'Video' : 'Voice'}_$cleanId";
    final url = Uri.parse(
      "https://meet.jit.si/$roomName#config.startWithAudioMuted=false&config.prejoinPageEnabled=false&config.startWithVideoMuted=${isVideo ? 'false' : 'true'}"
    );

    final primaryColor = isVideo ? const Color(0xFF4A90E2) : const Color(0xFF25D366);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryColor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: primaryColor,
                child: Icon(isVideo ? Icons.videocam : Icons.phone, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 8),
              Text(
                isVideo ? 'Video Call Active' : 'Voice Call Active',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isVideo
                ? 'High-definition video call is ready. Tap below to connect.'
                : 'Live voice call is active. Tap below to join with clear audio.',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              icon: Icon(isVideo ? Icons.videocam : Icons.call, size: 16),
              label: Text(isVideo ? 'Join Video Call' : 'Join Voice Call', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              onPressed: () async {
                try {
                  if (kIsWeb) {
                    await launchUrl(url, webOnlyWindowName: '_blank');
                  } else {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open call: $e')));
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotedReply() {
    if (message.replyTo == null) return const SizedBox.shrink();
    final reply = message.replyTo!;
    final sender = reply['senderName'] ?? 'Reply';
    final text = reply['text'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: Color(0xFFE94560), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sender,
            style: const TextStyle(
              color: Color(0xFFE94560),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionChips() {
    if (message.reactions.isEmpty) return const SizedBox.shrink();

    // Group counts by emoji
    final counts = <String, int>{};
    for (var emoji in message.reactions.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: counts.entries.map((entry) {
          final emoji = entry.key;
          final count = entry.value;
          final hasReacted = message.reactions[currentUserId] == emoji;

          return GestureDetector(
            onTap: () => onReactionToggle(emoji),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: hasReacted ? const Color(0xFFE94560).withOpacity(0.3) : Colors.black45,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasReacted ? const Color(0xFFE94560) : Colors.white12,
                  width: 1,
                ),
              ),
              child: Text(
                '$emoji ${count > 1 ? count : ''}',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVoiceCall = message.text.contains("Voice Call") || message.text.contains("voice call") || message.text.startsWith("📞");
    final isVideoCall = message.text.contains("Video Call") || message.text.contains("video call") || message.text.startsWith("📹");

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
          maxWidth: MediaQuery.of(context).size.width * 0.78,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quoted reply banner
            _buildQuotedReply(),

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

            // Call Cards
            if (isVoiceCall)
              _buildCallCard(context, isVideo: false)
            else if (isVideoCall)
              _buildCallCard(context, isVideo: true),

            // Photo Preview
            if (message.imageUrl != null && message.imageUrl!.isNotEmpty) ...[
              GestureDetector(
                onTap: () => _openFullImage(context, message.imageUrl!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      _buildImageWidget(message.imageUrl!, height: 220, width: double.infinity),
                      Container(
                        margin: const EdgeInsets.all(6),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.fullscreen, color: Colors.white70, size: 16),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],

            // Video Preview
            if (message.videoUrl != null && message.videoUrl!.isNotEmpty) ...[
              _VideoMessagePlayer(videoUrl: message.videoUrl!, isMe: isMe),
              const SizedBox(height: 6),
            ],

            // Audio Player
            if (message.audioUrl != null && message.audioUrl!.isNotEmpty) ...[
              _AudioMessagePlayer(audioUrl: message.audioUrl!, isMe: isMe),
              const SizedBox(height: 6),
            ],

            // Text message (hide placeholder text if media or call was sent)
            if (!isVoiceCall &&
                !isVideoCall &&
                message.text.isNotEmpty &&
                message.text != "📷 Image" &&
                message.text != "📷 Photo" &&
                message.text != "🎥 Video" &&
                message.text != "🎤 Audio Note")
              Text(
                message.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.3,
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: _buildReactionChips()),
                Text(
                  DateFormat('dd MMM, HH:mm').format(message.timestamp),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  const _FullScreenImageViewer({Key? key, required this.imageUrl}) : super(key: key);

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  final TransformationController _controller = TransformationController();
  double _scale = 1.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _zoomIn() {
    setState(() {
      _scale = (_scale * 1.3).clamp(0.5, 5.0);
      _controller.value = Matrix4.identity()..scale(_scale);
    });
  }

  void _zoomOut() {
    setState(() {
      _scale = (_scale / 1.3).clamp(0.5, 5.0);
      _controller.value = Matrix4.identity()..scale(_scale);
    });
  }

  void _resetZoom() {
    setState(() {
      _scale = 1.0;
      _controller.value = Matrix4.identity();
    });
  }

  void _download() {
    final fileName = 'nexus_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
    downloadFileFromUrl(widget.imageUrl, fileName);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.download_done_rounded, color: Colors.greenAccent),
            SizedBox(width: 8),
            Text('Photo download started!'),
          ],
        ),
        backgroundColor: Color(0xFF16213E),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildImageWidget(String url) {
    if (url.startsWith('data:image')) {
      final b64 = url.contains(',') ? url.split(',').last : url;
      final bytes = base64Decode(b64);
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
        ),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(
          child: CircularProgressIndicator(color: Color(0xFFE94560)),
        );
      },
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Photo Viewer', style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.zoom_in, color: Colors.white),
            tooltip: 'Zoom In',
            onPressed: _zoomIn,
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out, color: Colors.white),
            tooltip: 'Zoom Out',
            onPressed: _zoomOut,
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded, color: Colors.white),
            tooltip: 'Reset Zoom',
            onPressed: _resetZoom,
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.greenAccent),
            tooltip: 'Download Photo',
            onPressed: _download,
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          transformationController: _controller,
          panEnabled: true,
          minScale: 0.5,
          maxScale: 6.0,
          onInteractionEnd: (_) {
            _scale = _controller.value.getMaxScaleOnAxis();
          },
          child: _buildImageWidget(widget.imageUrl),
        ),
      ),
    );
  }
}

class _VideoMessagePlayer extends StatefulWidget {
  final String videoUrl;
  final bool isMe;

  const _VideoMessagePlayer({Key? key, required this.videoUrl, required this.isMe}) : super(key: key);

  @override
  State<_VideoMessagePlayer> createState() => _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends State<_VideoMessagePlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) setState(() => _isInitialized = true);
      }).catchError((_) {
        if (mounted) setState(() => _hasError = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        height: 150,
        width: 220,
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.white54, size: 32),
              SizedBox(height: 4),
              Text('Video unavailable', style: TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Container(
        height: 180,
        width: 220,
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE94560)),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 230,
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: _controller.value.aspectRatio > 0 ? _controller.value.aspectRatio : 16 / 9,
              child: VideoPlayer(_controller),
            ),
            IconButton(
              iconSize: 46,
              icon: Icon(
                _controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                color: Colors.white.withOpacity(0.9),
              ),
              onPressed: () {
                setState(() {
                  _controller.value.isPlaying ? _controller.pause() : _controller.play();
                });
              },
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                _controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Color(0xFFE94560),
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.black38,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioMessagePlayer extends StatefulWidget {
  final String audioUrl;
  final bool isMe;

  const _AudioMessagePlayer({Key? key, required this.audioUrl, required this.isMe}) : super(key: key);

  @override
  State<_AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<_AudioMessagePlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initAudio();

    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  Future<void> _initAudio() async {
    try {
      if (widget.audioUrl.startsWith('data:audio')) {
        final b64 = widget.audioUrl.split(',').last;
        final bytes = base64Decode(b64);
        await _player.setSource(BytesSource(bytes));
      } else {
        await _player.setSource(UrlSource(widget.audioUrl));
      }
    } catch (_) {}
  }

  Future<void> _togglePlay() async {
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        if (_position > Duration.zero && _position < _duration) {
          await _player.resume();
        } else {
          if (widget.audioUrl.startsWith('data:audio')) {
            final b64 = widget.audioUrl.split(',').last;
            final bytes = base64Decode(b64);
            await _player.play(BytesSource(bytes));
          } else {
            await _player.play(UrlSource(widget.audioUrl));
          }
        }
      }
    } catch (_) {}
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              color: widget.isMe ? Colors.white : const Color(0xFFE94560),
              size: 32,
            ),
            onPressed: _togglePlay,
          ),
          Expanded(
            child: Slider(
              value: _position.inMilliseconds.toDouble().clamp(0.0, _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0),
              max: _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
              onChanged: (val) {
                _player.seek(Duration(milliseconds: val.toInt()));
              },
              activeColor: widget.isMe ? Colors.white : const Color(0xFFE94560),
              inactiveColor: Colors.white24,
            ),
          ),
          Text(
            _formatDuration(_position > Duration.zero ? _position : _duration),
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
