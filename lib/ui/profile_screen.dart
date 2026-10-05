import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();
  
  bool _isLoading = false;

  Future<void> _pickAndUploadImage() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 600);
      if (image == null) return;

      setState(() => _isLoading = true);

      // Read as bytes (works on both mobile and web)
      final Uint8List imageBytes = await image.readAsBytes();

      // Create storage reference
      final ref = _storage.ref().child('profile_images').child('${currentUser.uid}.jpg');

      // Upload task
      await ref.putData(imageBytes, SettableMetadata(contentType: 'image/jpeg'));
      
      // Get URL
      final downloadUrl = await ref.getDownloadURL();

      // Update Firestore
      await _firestore.collection('users').doc(currentUser.uid).update({
        'photoUrl': downloadUrl,
      });

      // Update FirebaseAuth user object optionally
      await currentUser.updatePhotoURL(downloadUrl);

      setState(() => _isLoading = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile photo updated!')));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error uploading photo: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore.collection('users').doc(currentUser?.uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          final String displayName = userData?['displayName'] ?? currentUser?.displayName ?? 'User';
          final String email = userData?['email'] ?? currentUser?.email ?? '';
          final String? photoUrl = userData?['photoUrl'] ?? currentUser?.photoURL;

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: const Color(0xFF533483),
                      backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                      child: (photoUrl == null || photoUrl.isEmpty)
                          ? Text(displayName[0].toUpperCase(), style: const TextStyle(fontSize: 40, color: Colors.white))
                          : null,
                    ),
                    if (_isLoading)
                      const Positioned.fill(
                        child: Center(child: CircularProgressIndicator(color: Colors.white)),
                      )
                    else
                      GestureDetector(
                        onTap: _pickAndUploadImage,
                        child: const CircleAvatar(
                          radius: 20,
                          backgroundColor: Color(0xFFE94560),
                          child: Icon(Icons.camera_alt, color: Colors.white, size: 20),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  displayName,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  email,
                  style: const TextStyle(fontSize: 16, color: Colors.white54),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
