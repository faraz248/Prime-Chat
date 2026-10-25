import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'ui/theme.dart';
import 'ui/auth_screen.dart';
import 'ui/home_screen.dart';
import 'ui/verify_email_screen.dart';
import 'providers/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return MaterialApp(
      title: 'NEXUS AI Chat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkCinematicTheme,
      home: authState.when(
        data: (user) {
          if (user != null) {
            // If the user's Gmail is not yet verified, require verification first
            if (!user.emailVerified) {
              return const VerifyEmailScreen();
            }
            // Verified and Logged in! Go to contacts/friends list.
            return const HomeScreen();
          }
          // Not logged in! Go to Auth screen.
          return const AuthScreen();
        },
        loading: () => const Scaffold(
          backgroundColor: Color(0xFF0F0C20),
          body: Center(
            child: CircularProgressIndicator(color: Color(0xFFE94560)),
          ),
        ),
        error: (e, st) => Scaffold(
          backgroundColor: const Color(0xFF0F0C20),
          body: Center(
            child: Text('Error: $e', style: const TextStyle(color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
