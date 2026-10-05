import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
        _secretTapCount = 0; // Reset if they stop tapping
      });
    }
  }

  // Generate a unique room ID between two users
  String getChatRoomId(String a, String b) {
    if (a.substring(0, 1).codeUnitAt(0) > b.substring(0, 1).codeUnitAt(0)) {
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
                if (pinController.text == '9090') { // Admin PIN
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
        child: const Icon(Icons.group_add, color: Colors.white),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen()));
        },
      ),
      appBar: AppBar(
        title: GestureDetector(
          onTap: _handleSecretTap,
          child: const Text('My Friends'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              showSearch(context: context, delegate: UserSearchDelegate());
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authServiceProvider).signOut(),
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          // Filter out the current user from the friends list
          final users = snapshot.data!.docs.where((doc) => doc.id != currentUserId).toList();
          
          return ListView(
            children: [
              // 1. AI Assistant Chat (Always Visible)
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('chatRooms').doc('ai_room_$currentUserId').snapshots(),
                builder: (context, roomSnapshot) {
                  bool hasUnread = false;
                  if (roomSnapshot.hasData && roomSnapshot.data!.exists) {
                    final data = roomSnapshot.data!.data() as Map<String, dynamic>;
                    hasUnread = data['hasUnread_$currentUserId'] ?? false;
                  }
                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE94560),
                      child: Icon(Icons.auto_awesome, color: Colors.white),
                    ),
                    title: const Text('AI Assistant', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Always online - Type @AI to talk', style: TextStyle(color: Colors.white54)),
                    trailing: hasUnread 
                      ? const CircleAvatar(radius: 6, backgroundColor: Colors.redAccent)
                      : const Icon(Icons.chat_bubble, color: Color(0xFFE94560)),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          chatRoomId: 'ai_room_$currentUserId', 
                          friendName: 'AI Assistant'
                        ),
                      ));
                    },
                  );
                }
              ),
              const Divider(color: Colors.white24, indent: 16, endIndent: 16),
              
              // Groups section
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('chatRooms')
                    .where('isGroup', isEqualTo: true)
                    .where('members', arrayContains: currentUserId)
                    .snapshots(),
                builder: (context, groupSnapshot) {
                  if (!groupSnapshot.hasData || groupSnapshot.data!.docs.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final groups = groupSnapshot.data!.docs;
                  return Column(
                    children: groups.map((group) {
                      final data = group.data() as Map<String, dynamic>;
                      final groupName = data['groupName'] ?? 'Unnamed Group';
                      final hasUnread = data['hasUnread_$currentUserId'] ?? false;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal,
                          child: Text(groupName[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(groupName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        subtitle: const Text('Group Chat', style: TextStyle(color: Colors.white54)),
                        trailing: hasUnread 
                          ? const CircleAvatar(radius: 6, backgroundColor: Colors.redAccent)
                          : const Icon(Icons.group, color: Color(0xFFE94560)),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ChatScreen(chatRoomId: group.id, friendName: groupName, isGroup: true),
                          ));
                        },
                      );
                    }).toList(),
                  );
                }
              ),

              // Helper text if no friends are found
              if (users.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(30.0),
                  child: Center(
                    child: Text(
                      "No other users found.\n\nTap the search icon to find your friends by name or email, or create a second account!", 
                      textAlign: TextAlign.center, 
                      style: TextStyle(color: Colors.white54, height: 1.5)
                    )
                  ),
                ),

              // 2. Real Friends List
              ...users.map((user) {
                final userName = user['displayName'] ?? 'Unknown User';
                final roomId = getChatRoomId(currentUserId ?? '', user.id);
                
                return StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('chatRooms').doc(roomId).snapshots(),
                  builder: (context, roomSnapshot) {
                    if (!roomSnapshot.hasData || !roomSnapshot.data!.exists) {
                      return const SizedBox.shrink();
                    }

                    bool hasUnread = false;
                    final data = roomSnapshot.data!.data() as Map<String, dynamic>;
                    hasUnread = data['hasUnread_$currentUserId'] ?? false;
                    
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF533483),
                        backgroundImage: (user.data() as Map<String, dynamic>).containsKey('photoUrl') && user['photoUrl'] != null && user['photoUrl'].toString().isNotEmpty 
                            ? NetworkImage(user['photoUrl']) 
                            : null,
                        child: ((user.data() as Map<String, dynamic>).containsKey('photoUrl') && user['photoUrl'] != null && user['photoUrl'].toString().isNotEmpty)
                            ? null
                            : Text(userName[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(userName, style: const TextStyle(color: Colors.white, fontSize: 18)),
                      subtitle: Text(user['email'] ?? '', style: const TextStyle(color: Colors.white54)),
                      trailing: hasUnread 
                        ? const CircleAvatar(radius: 6, backgroundColor: Colors.redAccent)
                        : const Icon(Icons.chat_bubble_outline, color: Color(0xFFE94560)),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ChatScreen(chatRoomId: roomId, friendName: userName),
                        ));
                      },
                    );
                  }
                );
              }).toList(),
            ],
          );
        },
      ),
    );
      }
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
            'Search users by name or email',
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
            child: const Center(child: CircularProgressIndicator()),
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
                'No user found',
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
                if (a.substring(0, 1).codeUnitAt(0) > b.substring(0, 1).codeUnitAt(0)) {
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
                      : Text(userName[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
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
