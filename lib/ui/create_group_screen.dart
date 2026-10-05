import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({Key? key}) : super(key: key);

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final Set<String> _selectedUserIds = {};
  bool _isLoading = false;

  void _createGroup() async {
    final groupName = _nameController.text.trim();
    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a group name')));
      return;
    }
    if (_selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one friend')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final members = _selectedUserIds.toList();
      members.add(currentUser.uid); // Add self to group

      final roomRef = FirebaseFirestore.instance.collection('chatRooms').doc();
      
      await roomRef.set({
        'isGroup': true,
        'groupName': groupName,
        'members': members,
        'adminId': currentUser.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': 'Group created',
        'lastMessageTime': FieldValue.serverTimestamp(),
      });

      setState(() => _isLoading = false);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group created successfully!')));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error creating group: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Group Chat'),
        actions: [
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.only(right: 16), child: CircularProgressIndicator(color: Colors.white)))
          else
            TextButton(
              onPressed: _createGroup,
              child: const Text('CREATE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Group Name',
                prefixIcon: Icon(Icons.group, color: Colors.white54),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Select Members', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('chatRooms').snapshots(),
              builder: (context, chatSnapshot) {
                if (!chatSnapshot.hasData) return const Center(child: CircularProgressIndicator());

                final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
                Set<String> friendIds = {};
                for (var doc in chatSnapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>?;
                  if (data != null && data['isGroup'] != true) {
                    if (doc.id.contains(currentUserId) && !doc.id.startsWith('ai_room_')) {
                       final ids = doc.id.split('_');
                       if (ids.length == 2) {
                          if (ids[0] == currentUserId) friendIds.add(ids[1]);
                          else if (ids[1] == currentUserId) friendIds.add(ids[0]);
                       }
                    }
                  }
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    
                    final users = snapshot.data!.docs.where((doc) => doc.id != currentUserId && friendIds.contains(doc.id)).toList();

                    if (users.isEmpty) {
                      return const Center(
                        child: Text(
                          "No friends found.\nYou can only add people you have chatted with.", 
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54)
                        )
                      );
                    }

                    return ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        final data = user.data() as Map<String, dynamic>;
                        final userName = data['displayName'] ?? 'Unknown User';
                        final isSelected = _selectedUserIds.contains(user.id);

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF533483),
                            backgroundImage: data.containsKey('photoUrl') && data['photoUrl'] != null && data['photoUrl'].toString().isNotEmpty 
                                ? NetworkImage(data['photoUrl']) 
                                : null,
                            child: (data.containsKey('photoUrl') && data['photoUrl'] != null && data['photoUrl'].toString().isNotEmpty)
                                ? null
                                : Text(userName[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                          ),
                          title: Text(userName, style: const TextStyle(color: Colors.white)),
                          subtitle: Text(data['email'] ?? '', style: const TextStyle(color: Colors.white54)),
                          trailing: isSelected 
                              ? const Icon(Icons.check_circle, color: Color(0xFFE94560))
                              : const Icon(Icons.circle_outlined, color: Colors.white24),
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedUserIds.remove(user.id);
                              } else {
                                _selectedUserIds.add(user.id);
                              }
                            });
                          },
                        );
                      },
                    );
                  },
                );
              }
            ),
          ),
        ],
      ),
    );
  }
}
