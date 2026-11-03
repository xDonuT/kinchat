import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'emulator.dart';
import 'services/notification_service.dart';
import 'services/theme_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    // The integration-test harness boots the app once itself, then the test
    // body calls main() again. A second default app is expected there.
    if (e.code != 'duplicate-app') rethrow;
  }
  if (!useEmulator) {
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kReleaseMode
            ? AndroidPlayIntegrityProvider()
            : AndroidDebugProvider(),
      );
    } catch (e) {
      debugPrint('App Check activation failed: $e');
    }
  }
  await connectToEmulators();
  await ThemeService.instance.load();
  await NotificationService.instance.init();
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) NotificationService.instance.handleSignedIn();
  });
  runApp(const KinChatApp());
}

class KinChatApp extends StatelessWidget {
  const KinChatApp({super.key});

  /// Soft retro pastels: my bubbles are mint, other people's are sky blue,
  /// in both light and dark. Pixelify Sans is applied app-wide.
  static ThemeData _themeFor(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final mint = dark ? const Color(0xFF8FD6AB) : const Color(0xFFB7E6C9);
    final sky = dark ? const Color(0xFF8AB8DE) : const Color(0xFFC2DDF5);
    final bg = dark ? const Color(0xFF10161A) : const Color(0xFFF4FAF6);
    final scheme = ColorScheme.fromSeed(
      seedColor: mint,
      brightness: brightness,
    ).copyWith(
      primary: mint,
      onPrimary: dark ? const Color(0xFF0E1F13) : const Color(0xFF1C3226),
      secondary: sky,
      onSecondary: dark ? const Color(0xFF0C1926) : const Color(0xFF1E2A37),
      surface: bg,
      onSurface: dark ? const Color(0xFFD9E5DD) : const Color(0xFF28322C),
      surfaceContainerHighest: sky,
      onSurfaceVariant: dark ? const Color(0xFF94A49B) : const Color(0xFF4F5E55),
    );
    return ThemeData(
      fontFamily: 'Geist Pixel',
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) => MaterialApp(
        title: 'KinChat',
        debugShowCheckedModeBanner: false,
        theme: _themeFor(Brightness.light),
        darkTheme: _themeFor(Brightness.dark),
        themeMode: ThemeService.instance.darkMode
            ? ThemeMode.dark
            : ThemeMode.light,
        navigatorKey: NotificationService.instance.navigatorKey,
        home: const AuthGate(),
        builder: (context, child) {
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
      ),
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
        return _AuthedHome(uid: user.uid, email: user.email ?? '');
      },
    );
  }
}

class _AuthedHome extends StatelessWidget {
  const _AuthedHome({required this.uid, required this.email});

  final String uid;
  final String email;

  @override
  Widget build(BuildContext context) {
    return HomeScreen(uid: uid, email: email);
  }
}