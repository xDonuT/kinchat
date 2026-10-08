import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../services/chat_service.dart';
import '../services/profile_service.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

/// The landing screen: one entry for the family group, then a list of people
/// to message privately. Tapping either pushes a full chat screen.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.uid, required this.email});

  final String uid;
  final String email;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ProfileService _profiles = ProfileService();

  @override
  void initState() {
    super.initState();
    // Make sure our own name exists so other people can see who we are.
    _profiles.ensureProfile(uid: widget.uid, email: widget.email);
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need your password to sign back in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
      // Root swaps to the login screen on sign-out; clear any pushed routes.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _openProfile(Map<String, String> names, Profile person) async {
    // Firestore rules only let the two participants read/reply in a 1:1
    // thread, and they learn who those two are from the conversation
    // document, so it must exist before the chat screen listens.
    final String roomId;
    try {
      roomId = await _profiles.openConversation(widget.uid, person.uid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start the chat: $e')),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          uid: widget.uid,
          room: ChatRoom.private(roomId),
          title: person.safeName,
          names: names,
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(uid: widget.uid, email: widget.email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KinChat'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<List<Profile>>(
        stream: _profiles.watchMembers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load the family list.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final members = snapshot.data ?? const <Profile>[];
          final names = <String, String>{
            for (final p in members) p.uid: p.safeName,
          };
          // Until profiles load, still offer the group chat.
          final others = members.where((p) => p.uid != widget.uid).toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              const _SectionHeader(label: 'Chats'),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.group)),
                title: const Text('Family'),
                subtitle: const Text('Everyone in one room'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChatScreen(
                        uid: widget.uid,
                        room: const ChatRoom.group(),
                        title: 'Family',
                        names: names,
                        showSenderNames: true,
                      ),
                    ),
                  );
                },
              ),
              const _SectionHeader(label: 'People'),
              if (others.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    'Nobody else has opened the app yet.',
                    style: TextStyle(color: Colors.black54),
                  ),
                )
              else
                for (final person in others)
                  ListTile(
                    leading: CircleAvatar(child: Text(_initials(person.safeName))),
                    title: Text(person.safeName),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openProfile(names, person),
                  ),
            ],
          );
        },
      ),
    );
  }

  static String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
