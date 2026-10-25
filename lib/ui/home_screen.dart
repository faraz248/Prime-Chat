import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../providers/providers.dart';
import 'chat_screen.dart';
import 'admin_panel.dart';
import 'profile_screen.dart';
import 'create_group_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  int _secretTapCount = 0;
  Timer? _tapTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateLastSeen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateLastSeen();
    }
  }

  void _updateLastSeen() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'lastSeen': FieldValue.serverTimestamp(),
      }).catchError((_) {});
    }
  }

  void _handleSecretTap() {
    _secretTapCount++;
    if (_secretTapCount >= 7) {
      _secretTapCount = 0;
      _showAdminDialog();
    } else {
      _tapTimer?.cancel();
      _tapTimer = Timer(const Duration(seconds: 2), () {
        _secretTapCount = 0;
      });
    }
  }

  String _formatMessageTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0 && dt.day == now.day) {
      return DateFormat('hh:mm a').format(dt);
    } else if (diff.inDays == 1 || (diff.inDays == 0 && dt.day != now.day)) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return DateFormat('E').format(dt);
    } else {
      return DateFormat('dd MMM').format(dt);
    }
  }

  // Deterministic, commutative room ID for two users
  String getChatRoomId(String a, String b) {
    if (a.compareTo(b) > 0) {
      return "${b}_$a";
    } else {
      return "${a}_$b";
    }
  }

  void _showAdminDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final pinController = TextEditingController();
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('Admin Access', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: pinController,
            keyboardType: TextInputType.number,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: 'Enter PIN', hintStyle: TextStyle(color: Colors.white54)),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (pinController.text == '9090') {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanel()));
                } else {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect PIN')));
                }
              },
              child: const Text('Login', style: TextStyle(color: Colors.redAccent)),
            )
          ],
        );
      }
    );
  }

  void _showNewChatMenu(BuildContext context) {
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
              color: Colors.black.withOpacity(0.6),
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
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFFE94560), Color(0xFF533483)]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_search_rounded, color: Colors.white, size: 22),
              ),
              title: const Text('New Direct Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('Search friend by name or email', style: TextStyle(color: Colors.white54, fontSize: 13)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 16),
              onTap: () {
                Navigator.pop(ctx);
                showSearch(context: context, delegate: UserSearchDelegate());
              },
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0xFF16213E),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.group_add_rounded, color: Color(0xFFE94560), size: 22),
              ),
              title: const Text('New Group', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('Create a group with your friends', style: TextStyle(color: Colors.white54, fontSize: 13)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 16),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(currentUserId).snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.hasData && userSnapshot.data!.exists) {
          final data = userSnapshot.data!.data() as Map<String, dynamic>;
          if (data['isBlocked'] == true) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Account Suspended'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.logout),
                    onPressed: () => ref.read(authServiceProvider).signOut(),
                  )
                ],
              ),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.block, color: Colors.redAccent, size: 80),
                    SizedBox(height: 20),
                    Text('ACCOUNT SUSPENDED', style: TextStyle(color: Colors.redAccent, fontSize: 24, fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),
                    Text('Your account has been blocked by the admin.', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            );
          }
        }

        return Scaffold(
          floatingActionButton: FloatingActionButton(
            backgroundColor: const Color(0xFFE94560),
            tooltip: 'Start a Chat',
            child: const Icon(Icons.message_rounded, color: Colors.white),
            onPressed: () => _showNewChatMenu(context),
          ),
          appBar: AppBar(
            title: GestureDetector(
              onTap: _handleSecretTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFE94560), Color(0xFF533483)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.bolt, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'NEXUS CHAT',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      fontSize: 19,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.person),
                tooltip: 'My Profile',
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                },
              ),
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'Search Friends',
                onPressed: () {
                  showSearch(context: context, delegate: UserSearchDelegate());
                },
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Sign Out',
                onPressed: () => ref.read(authServiceProvider).signOut(),
              )
            ],
          ),
          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').snapshots(),
            builder: (context, usersSnapshot) {
              if (!usersSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFFE94560)));
              }

              final Map<String, Map<String, dynamic>> usersMap = {};
              for (var doc in usersSnapshot.data!.docs) {
                usersMap[doc.id] = doc.data() as Map<String, dynamic>;
              }

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('chatRooms').snapshots(),
                builder: (context, roomsSnapshot) {
                  if (!roomsSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFFE94560)));
                  }

                  final roomDocs = roomsSnapshot.data!.docs;

                  // 1. Check AI Assistant room document if exists
                  DocumentSnapshot? aiRoomDoc;
                  try {
                    aiRoomDoc = roomDocs.firstWhere((d) => d.id == 'ai_room_$currentUserId');
                  } catch (_) {
                    aiRoomDoc = null;
                  }

                  // 2. Filter active conversations for this user (excluding AI room)
                  List<DocumentSnapshot> myRooms = roomDocs.where((doc) {
                    if (doc.id.startsWith('ai_room_')) return false;
                    final data = doc.data() as Map<String, dynamic>;
                    if (data['members'] is List && (data['members'] as List).contains(currentUserId)) return true;
                    if (doc.id.contains(currentUserId ?? '')) return true;
                    return false;
                  }).toList();

                  // Sort active conversations by latest message time descending
                  myRooms.sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    final aTime = (aData['lastMessageTime'] as Timestamp?)?.toDate() ?? DateTime.now();
                    final bTime = (bData['lastMessageTime'] as Timestamp?)?.toDate() ?? DateTime.now();
                    return bTime.compareTo(aTime);
                  });

                  return ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      // PINNED AI ASSISTANT TILE (Always at the top)
                      _buildAiAssistantTile(context, aiRoomDoc, currentUserId),

                      if (myRooms.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                          child: Text(
                            'CHATS',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        ...myRooms.map((room) {
                          final data = room.data() as Map<String, dynamic>;
                          final isGroup = data['isGroup'] == true;

                          String title = 'Chat';
                          String subtitle = data['lastMessage'] ?? '';
                          Widget leadingWidget;
                          Timestamp? lastTime = data['lastMessageTime'] as Timestamp?;

                          // Robust unread count parser
                          int unreadCount = 0;
                          final rawUnread = data['unreadCount_$currentUserId'];
                          if (rawUnread is num) {
                            unreadCount = rawUnread.toInt();
                          } else if (rawUnread != null) {
                            unreadCount = int.tryParse(rawUnread.toString()) ?? 0;
                          } else if (data['hasUnread_$currentUserId'] == true) {
                            unreadCount = 1;
                          }

                          if (isGroup) {
                            title = data['groupName'] ?? 'Unnamed Group';
                            if (subtitle.isEmpty) subtitle = 'Group Chat';
                            leadingWidget = CircleAvatar(
                              radius: 25,
                              backgroundColor: Colors.teal.shade700,
                              child: Text(
                                title.isNotEmpty ? title[0].toUpperCase() : 'G',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            );
                          } else {
                            // 1-on-1 chat
                            final ids = room.id.split('_');
                            final otherId = ids.length == 2 ? (ids[0] == currentUserId ? ids[1] : ids[0]) : '';
                            final otherUserData = usersMap[otherId];
                            title = otherUserData?['displayName'] ?? 'Friend';
                            if (subtitle.isEmpty) subtitle = otherUserData?['email'] ?? '';

                            final lastSeen = otherUserData?['lastSeen'] as Timestamp?;
                            final isOnline = lastSeen != null && DateTime.now().difference(lastSeen.toDate()).inMinutes < 2;

                            leadingWidget = Stack(
                              children: [
                                CircleAvatar(
                                  radius: 25,
                                  backgroundColor: const Color(0xFF533483),
                                  backgroundImage: otherUserData?['photoUrl'] != null && otherUserData!['photoUrl'].toString().isNotEmpty
                                      ? NetworkImage(otherUserData['photoUrl'])
                                      : null,
                                  child: otherUserData?['photoUrl'] != null && otherUserData!['photoUrl'].toString().isNotEmpty
                                      ? null
                                      : Text(
                                          title.isNotEmpty ? title[0].toUpperCase() : 'U',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                                        ),
                                ),
                                if (isOnline)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: Colors.greenAccent,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: const Color(0xFF0D0D12), width: 2.5),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          }

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: leadingWidget,
                            title: Text(
                              title,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                subtitle,
                                style: TextStyle(
                                  color: unreadCount > 0 ? Colors.white : Colors.white54,
                                  fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (lastTime != null)
                                  Text(
                                    _formatMessageTime(lastTime.toDate()),
                                    style: TextStyle(
                                      color: unreadCount > 0 ? const Color(0xFFE94560) : Colors.white38,
                                      fontSize: 11,
                                      fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                if (unreadCount > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFFE94560), Color(0xFF533483)],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFE94560).withOpacity(0.5),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      unreadCount > 9 ? '9+' : '$unreadCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  chatRoomId: room.id,
                                  friendName: title,
                                  isGroup: isGroup,
                                ),
                              ));
                            },
                          );
                        }).toList(),
                      ] else ...[
                        // Empty state when user hasn't chatted with anyone yet
                        Container(
                          margin: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF16213E).withOpacity(0.4),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_outline_rounded, size: 54, color: Colors.white.withOpacity(0.3)),
                              const SizedBox(height: 14),
                              const Text(
                                'No Conversations Yet',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Search for a friend by name or email, or tap the button below to start chatting!',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
                              ),
                              const SizedBox(height: 18),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE94560),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                ),
                                icon: const Icon(Icons.person_search_rounded, size: 18),
                                label: const Text('Find Friends'),
                                onPressed: () {
                                  showSearch(context: context, delegate: UserSearchDelegate());
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              );
            },
          ),
        );
      }
    );
  }

  Widget _buildAiAssistantTile(BuildContext context, DocumentSnapshot? aiRoomDoc, String? currentUserId) {
    String aiLastMessage = 'Always online • Ask questions & search photos';
    Timestamp? aiLastTime;
    int aiUnread = 0;

    if (aiRoomDoc != null && aiRoomDoc.exists) {
      final data = aiRoomDoc.data() as Map<String, dynamic>;
      if (data['lastMessage'] != null && data['lastMessage'].toString().isNotEmpty) {
        aiLastMessage = data['lastMessage'];
      }
      aiLastTime = data['lastMessageTime'] as Timestamp?;
      final rawUnread = data['unreadCount_$currentUserId'];
      if (rawUnread is num) {
        aiUnread = rawUnread.toInt();
      } else if (data['hasUnread_$currentUserId'] == true) {
        aiUnread = 1;
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE94560).withOpacity(0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE94560).withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 50,
          height: 50,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE94560), Color(0xFF533483)],
            ),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
        ),
        title: Row(
          children: [
            const Text(
              'AI Assistant',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE94560).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('PRO', style: TextStyle(color: Color(0xFFE94560), fontSize: 9, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            aiLastMessage,
            style: TextStyle(
              color: aiUnread > 0 ? Colors.white : Colors.white60,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (aiLastTime != null)
              Text(
                _formatMessageTime(aiLastTime.toDate()),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            const SizedBox(height: 4),
            if (aiUnread > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE94560), Color(0xFF533483)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  aiUnread > 9 ? '9+' : '$aiUnread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatRoomId: 'ai_room_$currentUserId',
              friendName: 'AI Assistant',
            ),
          ));
        },
      ),
    );
  }
}

class UserSearchDelegate extends SearchDelegate {
  @override
  ThemeData appBarTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0D0D12),
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white54),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      )
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    if (query.trim().isEmpty) {
      return Container(
        color: const Color(0xFF0D0D12),
        child: const Center(
          child: Text(
            'Type a friend\'s name or email to search',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final lowercaseQuery = query.toLowerCase();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            color: const Color(0xFF0D0D12),
            child: const Center(child: CircularProgressIndicator(color: Color(0xFFE94560))),
          );
        }

        final users = snapshot.data!.docs.where((doc) {
          if (doc.id == currentUserId) return false;
          final name = (doc['displayName'] ?? '').toString().toLowerCase();
          final email = (doc['email'] ?? '').toString().toLowerCase();
          return name.contains(lowercaseQuery) || email.contains(lowercaseQuery);
        }).toList();

        if (users.isEmpty) {
          return Container(
            color: const Color(0xFF0D0D12),
            child: const Center(
              child: Text(
                'No user found matching that name or email',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          );
        }

        return Container(
          color: const Color(0xFF0D0D12),
          child: ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final userName = user['displayName'] ?? 'Unknown User';
              
              String getChatRoomId(String a, String b) {
                if (a.compareTo(b) > 0) {
                  return "${b}_$a";
                } else {
                  return "${a}_$b";
                }
              }
              final roomId = getChatRoomId(currentUserId ?? '', user.id);

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF533483),
                  backgroundImage: (user.data() as Map<String, dynamic>).containsKey('photoUrl') && user['photoUrl'] != null && user['photoUrl'].toString().isNotEmpty 
                      ? NetworkImage(user['photoUrl']) 
                      : null,
                  child: ((user.data() as Map<String, dynamic>).containsKey('photoUrl') && user['photoUrl'] != null && user['photoUrl'].toString().isNotEmpty)
                      ? null
                      : Text(userName.isNotEmpty ? userName[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white)),
                ),
                title: Text(userName, style: const TextStyle(color: Colors.white)),
                subtitle: Text(user['email'] ?? '', style: const TextStyle(color: Colors.white54)),
                trailing: const Icon(Icons.message, color: Color(0xFFE94560)),
                onTap: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(
                    builder: (_) => ChatScreen(chatRoomId: roomId, friendName: userName),
                  ));
                },
              );
            },
          ),
        );
      },
    );
  }
}
