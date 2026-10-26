import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'admin_chat_view.dart';

class AdminPanel extends StatefulWidget {
  const AdminPanel({Key? key}) : super(key: key);

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  Map<String, String> userNames = {};
  int _selectedIndex = 0;
  String _chatSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  // Database se sabhi users ke asli naam nikal rahe hain
  Future<void> _fetchUsers() async {
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    final Map<String, String> names = {};
    for (var doc in snapshot.docs) {
      names[doc.id] = doc.data()['displayName'] ?? 'Unknown';
    }
    setState(() {
      userNames = names;
    });
  }

  // Room ID ko convert karke asli naam show karna
  String _getRoomName(String roomId) {
    if (userNames.isEmpty) return 'Loading names...';
    
    // Agar AI se baat ho rahi hai
    if (roomId.startsWith('ai_room_')) {
      final userId = roomId.replaceAll('ai_room_', '');
      final userName = userNames[userId] ?? 'Unknown';
      return '$userName 🤖 AI Assistant';
    }

    // Agar do doston me baat ho rahi hai (e.g. user1_user2)
    final ids = roomId.split('_');
    if (ids.length == 2) {
      final name1 = userNames[ids[0]] ?? 'Unknown 1';
      final name2 = userNames[ids[1]] ?? 'Unknown 2';
      return '$name1 💬 $name2';
    }
    
    return roomId; // Fallback
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedIndex == 0 ? 'Admin Secret Panel' : 
          _selectedIndex == 1 ? 'AI Chat History' : 
          _selectedIndex == 2 ? 'Deleted Messages' : 
          _selectedIndex == 3 ? 'Registered Users' : 'All Groups', 
          style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)
        ),
        backgroundColor: const Color(0xFF1A1A2E),
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF1A1A2E),
        child: ListView(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFFE94560)),
              child: Text('Admin Menu', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.chat, color: Colors.white),
              title: const Text('All Chats', style: TextStyle(color: Colors.white)),
              onTap: () {
                setState(() => _selectedIndex = 0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.psychology_rounded, color: Colors.amberAccent),
              title: const Text('AI Chats History (User 🤖)', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
              onTap: () {
                setState(() => _selectedIndex = 1);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep, color: Colors.redAccent),
              title: const Text('Deleted Messages', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                setState(() => _selectedIndex = 2);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.people, color: Colors.blueAccent),
              title: const Text('Registered Users', style: TextStyle(color: Colors.blueAccent)),
              onTap: () {
                setState(() => _selectedIndex = 3);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_work, color: Colors.greenAccent),
              title: const Text('All Groups', style: TextStyle(color: Colors.greenAccent)),
              onTap: () {
                setState(() => _selectedIndex = 4);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: _selectedIndex == 4 ? _buildGroupsList() : 
            _selectedIndex == 3 ? _buildUsersList() : 
            _selectedIndex == 2 ? _buildDeletedMessagesFeed() : 
            _selectedIndex == 1 ? _buildAiChatsList() : _buildChatsList(),
    );
  }

  Future<void> _toggleBlockStatus(String userId, bool currentStatus) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'isBlocked': !currentStatus,
    });
  }

  void _showFriendsDialog(BuildContext context, String userName, List<String> friendIds) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: Text('$userName\'s Friends', style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: friendIds.isEmpty 
              ? const Text('No friends yet.', style: TextStyle(color: Colors.white54))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: friendIds.length,
                  itemBuilder: (context, idx) {
                    final fName = userNames[friendIds[idx]] ?? 'Unknown';
                    return ListTile(
                      leading: const Icon(Icons.person, color: Colors.blueAccent),
                      title: Text(fName, style: const TextStyle(color: Colors.white)),
                    );
                  }
                ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: Colors.redAccent)),
            )
          ],
        );
      }
    );
  }

  void _showGroupMembersDialog(BuildContext context, String groupName, List<dynamic> memberIds) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: Text('Members of $groupName', style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: memberIds.isEmpty 
              ? const Text('No members.', style: TextStyle(color: Colors.white54))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: memberIds.length,
                  itemBuilder: (context, idx) {
                    final memberId = memberIds[idx].toString();
                    final mName = userNames[memberId] ?? 'Unknown User';
                    return ListTile(
                      leading: const Icon(Icons.person, color: Colors.greenAccent),
                      title: Text(mName, style: const TextStyle(color: Colors.white)),
                    );
                  }
                ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: Colors.redAccent)),
            )
          ],
        );
      }
    );
  }

  // 🤖 All AI Assistant conversations across users
  Widget _buildAiChatsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('chatRooms').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.amberAccent));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No AI conversations found.', style: TextStyle(color: Colors.white54)));
        }

        final aiRooms = snapshot.data!.docs.where((doc) => doc.id.startsWith('ai_room_')).toList();

        if (aiRooms.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.smart_toy_outlined, color: Colors.amberAccent, size: 54),
                SizedBox(height: 12),
                Text('No user has chatted with AI Assistant yet.', style: TextStyle(color: Colors.white54)),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: aiRooms.length,
          padding: const EdgeInsets.all(10),
          itemBuilder: (context, index) {
            final room = aiRooms[index];
            final data = room.data() as Map<String, dynamic>?;
            final userId = room.id.replaceAll('ai_room_', '');
            final userName = userNames[userId] ?? 'User ($userId)';
            final lastMsg = data?['lastMessage'] ?? 'AI Chat session...';
            final lastTime = (data?['lastMessageTime'] as Timestamp?)?.toDate();
            final timeStr = lastTime != null ? DateFormat('dd MMM, hh:mm a').format(lastTime) : '';

            return Card(
              color: const Color(0xFF16213E),
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.amberAccent.withOpacity(0.35)),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.psychology_rounded, color: Colors.amberAccent, size: 24),
                ),
                title: Row(
                  children: [
                    Text(userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE94560).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('AI CHAT', style: TextStyle(color: Color(0xFFE94560), fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(lastMsg, style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (timeStr.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(timeStr, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ],
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.amberAccent, size: 16),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AdminChatView(
                      chatRoomId: room.id,
                      roomName: '$userName 🤖 AI Assistant',
                      userNames: userNames,
                      showOnlyDeleted: false,
                    ),
                  ));
                },
              ),
            );
          },
        );
      },
    );
  }

  // 🗑️ Feed of Deleted Messages with "thoda light" appearance and who deleted it
  Widget _buildDeletedMessagesFeed() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collectionGroup('messages').where('isDeleted', isEqualTo: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No deleted messages found across the app.', style: TextStyle(color: Colors.white54)));
        }

        final docs = snapshot.data!.docs.toList();
        docs.sort((a, b) {
          final aTime = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          final bTime = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime);
        });

        return ListView.builder(
          itemCount: docs.length,
          padding: const EdgeInsets.all(8),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final text = data['text'] ?? '';
            final senderId = data['senderId'] ?? '';
            final senderName = userNames[senderId] ?? 'Unknown User';
            final deletedByName = data['deletedByName'] ?? 
                (data['deletedBy'] != null ? userNames[data['deletedBy']] : senderName);

            final timestamp = data['timestamp'] as Timestamp?;
            final timeStr = timestamp != null ? DateFormat('dd MMM, hh:mm a').format(timestamp.toDate()) : '';
            final delTs = data['deletedAt'] as Timestamp?;
            final delTimeStr = delTs != null ? DateFormat('dd MMM, hh:mm a').format(delTs.toDate()) : '';
            
            String roomId = 'Unknown Room';
            if (doc.reference.parent.parent != null) {
              roomId = doc.reference.parent.parent!.id;
            }
            final roomName = _getRoomName(roomId);

            return Card(
              color: const Color(0xFF1E1420), // "thoda light" translucent dark card
              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.redAccent.withOpacity(0.35)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AdminChatView(
                      chatRoomId: roomId,
                      roomName: roomName,
                      userNames: userNames,
                      showOnlyDeleted: false,
                    ),
                  ));
                },
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.delete_forever, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                                children: [
                                  TextSpan(text: deletedByName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                                  const TextSpan(text: ' deleted message from '),
                                  TextSpan(text: senderName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                                  const TextSpan(text: ' in '),
                                  TextSpan(text: roomName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
                        ),
                        child: Text(
                          '"$text"', 
                          style: const TextStyle(color: Colors.white70, fontSize: 14, fontStyle: FontStyle.italic),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Deleted: $delTimeStr', style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
                          Text('Sent: $timeStr', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 👥 Registered Users List with 1-click AI Chat History access
  Widget _buildUsersList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('chatRooms').snapshots(),
          builder: (context, chatSnapshot) {
            if (!chatSnapshot.hasData) return const Center(child: CircularProgressIndicator());

            final users = userSnapshot.data!.docs;
            final chats = chatSnapshot.data!.docs;
            
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Total Users: ${users.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final data = user.data() as Map<String, dynamic>;
                      final name = data['displayName'] ?? 'Unknown';
                      final email = data['email'] ?? 'No email';
                      final photoUrl = data['photoUrl'];

                      final isBlocked = data['isBlocked'] == true;

                      // Calculate friends (private chats) and groups
                      List<String> friendIds = [];
                      int groupChats = 0;
                      for (var chat in chats) {
                        final chatData = chat.data() as Map<String, dynamic>?;
                        if (chatData != null && chatData['isGroup'] == true) {
                          final members = chatData['members'] as List<dynamic>? ?? [];
                          if (members.contains(user.id)) groupChats++;
                        } else {
                          if (chat.id.contains(user.id) && !chat.id.startsWith('ai_room_')) {
                             final ids = chat.id.split('_');
                             if (ids.length == 2) {
                               if (ids[0] == user.id) friendIds.add(ids[1]);
                               else if (ids[1] == user.id) friendIds.add(ids[0]);
                             }
                          }
                        }
                      }

                      return Card(
                        color: const Color(0xFF16213E),
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF533483),
                            backgroundImage: photoUrl != null && photoUrl.toString().isNotEmpty 
                                ? NetworkImage(photoUrl) 
                                : null,
                            child: (photoUrl != null && photoUrl.toString().isNotEmpty)
                                ? null
                                : Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white)),
                          ),
                          title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(email, style: const TextStyle(color: Colors.white70)),
                              const SizedBox(height: 4),
                              GestureDetector(
                                onTap: () => _showFriendsDialog(context, name, friendIds),
                                child: Text(
                                  'Friends: ${friendIds.length} | Groups: $groupChats', 
                                  style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 🤖 1-Click AI Assistant History Button
                              IconButton(
                                icon: const Icon(Icons.psychology_rounded, color: Colors.amberAccent),
                                tooltip: 'View $name\'s AI Chat History',
                                onPressed: () {
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => AdminChatView(
                                      chatRoomId: 'ai_room_${user.id}',
                                      roomName: '$name 🤖 AI History',
                                      userNames: userNames,
                                      showOnlyDeleted: false,
                                    ),
                                  ));
                                },
                              ),
                              Text(isBlocked ? 'Blocked' : 'Active', style: TextStyle(color: isBlocked ? Colors.redAccent : Colors.green)),
                              Switch(
                                value: isBlocked,
                                activeColor: Colors.redAccent,
                                onChanged: (val) => _toggleBlockStatus(user.id, isBlocked),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          }
        );
      },
    );
  }

  // 💬 All Chats (User-to-User & Groups)
  Widget _buildChatsList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search by user or group name...',
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.search, color: Colors.redAccent),
              filled: true,
              fillColor: const Color(0xFF16213E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) {
              setState(() {
                _chatSearchQuery = val.toLowerCase();
              });
            },
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('chatRooms').orderBy('lastMessageTime', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                 return const Center(child: Text('No chats exist yet.', style: TextStyle(color: Colors.white)));
              }
              
              var rooms = snapshot.data!.docs;

              if (_chatSearchQuery.isNotEmpty) {
                rooms = rooms.where((room) {
                  final data = room.data() as Map<String, dynamic>?;
                  final roomName = data != null && data['isGroup'] == true ? (data['groupName'] ?? 'Group Chat') : _getRoomName(room.id);
                  return roomName.toLowerCase().contains(_chatSearchQuery);
                }).toList();
              }

              if (rooms.isEmpty) {
                return const Center(child: Text('No matching chats found.', style: TextStyle(color: Colors.white)));
              }

              return ListView.builder(
                itemCount: rooms.length,
                itemBuilder: (context, index) {
                  final room = rooms[index];
                  final data = room.data() as Map<String, dynamic>?;
                  final lastMsg = data != null && data.containsKey('lastMessage') ? data['lastMessage'] : 'Chat history...';
                  
                  final roomName = data != null && data['isGroup'] == true ? (data['groupName'] ?? 'Group Chat') : _getRoomName(room.id);
                  
                  return Card(
                    color: const Color(0xFF16213E),
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: ListTile(
                      leading: Icon(
                        room.id.startsWith('ai_room_') 
                            ? Icons.psychology_rounded 
                            : (data != null && data['isGroup'] == true ? Icons.group : Icons.security), 
                        color: room.id.startsWith('ai_room_') ? Colors.amberAccent : Colors.redAccent,
                      ),
                      title: Text(roomName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      subtitle: Text('Latest: $lastMsg', style: const TextStyle(color: Colors.white54), maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.visibility, color: Colors.redAccent),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => AdminChatView(
                            chatRoomId: room.id, 
                            roomName: roomName,
                            userNames: userNames,
                            showOnlyDeleted: false,
                          ),
                        ));
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // 👥 All Groups
  Widget _buildGroupsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('chatRooms').where('isGroup', isEqualTo: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
           return const Center(child: Text('No groups have been created yet.', style: TextStyle(color: Colors.white)));
        }
        
        final groups = snapshot.data!.docs;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Total Groups: ${groups.length}',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: groups.length,
                itemBuilder: (context, index) {
                  final group = groups[index];
                  final data = group.data() as Map<String, dynamic>;
                  final groupName = data['groupName'] ?? 'Unnamed Group';
                  final members = data['members'] as List<dynamic>? ?? [];
                  final creatorId = data['adminId'] ?? '';
                  final creatorName = userNames[creatorId] ?? 'Unknown Admin';
                  
                  return Card(
                    color: const Color(0xFF16213E),
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.teal,
                        child: Icon(Icons.group, color: Colors.white),
                      ),
                      title: Text(groupName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => _showGroupMembersDialog(context, groupName, members),
                            child: Text(
                              'Members: ${members.length} (Tap to view)', 
                              style: const TextStyle(color: Colors.blueAccent, decoration: TextDecoration.underline),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text('Created by: $creatorName', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                      trailing: const Icon(Icons.visibility, color: Colors.redAccent),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => AdminChatView(
                            chatRoomId: group.id, 
                            roomName: groupName,
                            userNames: userNames,
                            showOnlyDeleted: false,
                          ),
                        ));
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
