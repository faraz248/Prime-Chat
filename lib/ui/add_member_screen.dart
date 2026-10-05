import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddMemberScreen extends StatefulWidget {
  final String chatRoomId;
  const AddMemberScreen({Key? key, required this.chatRoomId}) : super(key: key);

  @override
  State<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends State<AddMemberScreen> {
  final Set<String> _selectedUserIds = {};
  bool _isLoading = false;

  void _addMembers() async {
    if (_selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one friend')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final roomRef = FirebaseFirestore.instance.collection('chatRooms').doc(widget.chatRoomId);
      
      await roomRef.update({
        'members': FieldValue.arrayUnion(_selectedUserIds.toList()),
      });

      setState(() => _isLoading = false);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Members added successfully!')));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error adding members: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Members'),
        actions: [
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.only(right: 16), child: CircularProgressIndicator(color: Colors.white)))
          else
            TextButton(
              onPressed: _addMembers,
              child: const Text('ADD', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            )
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('chatRooms').doc(widget.chatRoomId).snapshots(),
        builder: (context, groupSnapshot) {
          if (!groupSnapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final groupData = groupSnapshot.data!.data() as Map<String, dynamic>?;
          final existingMembers = List<dynamic>.from(groupData?['members'] ?? []);

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('chatRooms').snapshots(),
            builder: (context, chatSnapshot) {
              if (!chatSnapshot.hasData) return const Center(child: CircularProgressIndicator());

              Set<String> friendIds = {};
              for (var doc in chatSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>?;
                if (data != null && data['isGroup'] != true) {
                  if (doc.id.contains(currentUserId ?? '') && !doc.id.startsWith('ai_room_')) {
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
                  
                  // Filter out current user, people already in the group, and non-friends
                  final users = snapshot.data!.docs.where((doc) => 
                      doc.id != currentUserId && 
                      friendIds.contains(doc.id) && 
                      !existingMembers.contains(doc.id)
                  ).toList();

                  if (users.isEmpty) {
                    return const Center(
                      child: Text(
                        "No friends available to add.\nAll your friends are already in this group.", 
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
          );
        }
      ),
    );
  }
}
