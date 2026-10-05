import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool isLogin = true;
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController(); // For Signup

  void submit() async {
    final auth = ref.read(authServiceProvider);
    try {
      if (isLogin) {
        await auth.signInWithEmailPassword(
          emailController.text.trim(), 
          passwordController.text.trim()
        );
      } else {
        await auth.signUpWithEmailPassword(
          emailController.text.trim(), 
          passwordController.text.trim(), 
          nameController.text.trim()
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e', style: const TextStyle(color: Colors.white)))
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isLogin ? 'Welcome Back' : 'Join NEXUS'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isLogin) ...[
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Your Name (e.g. Rahul)'),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email Address'),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE94560),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: submit,
                child: Text(isLogin ? 'LOGIN' : 'SIGN UP', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => setState(() => isLogin = !isLogin),
              child: Text(
                isLogin ? 'New here? Create an account' : 'Already have an account? Login',
                style: const TextStyle(color: Colors.white70),
              ),
            )
          ],
        ),
      ),
    );
  }
}
