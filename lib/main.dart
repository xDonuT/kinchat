import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'emulator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await connectToEmulators();
  runApp(const KinChatApp());
}

class KinChatApp extends StatelessWidget {
  const KinChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KinChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E6F40)),
        useMaterial3: true,
      ),
      home: const AuthGate(),
      builder: (context, child) {
        // A loud stripe so emulator runs are never mistaken for the real app.
        if (!useEmulator) return child!;
        return Column(
          children: [
            Material(
              color: const Color(0xFFFFB300),
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(
                      'TEST MODE - $emulatorBannerText',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: child!),
          ],
        );
      },
    );
  }
}

/// Watches the auth state and swaps between the login screen and the chat.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) return const LoginScreen();
        return _AuthedHome(uid: user.uid);
      },
    );
  }
}

class _AuthedHome extends StatelessWidget {
  const _AuthedHome({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return ChatScreen(uid: uid);
  }
}