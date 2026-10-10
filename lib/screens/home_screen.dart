import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../services/chat_service.dart';
import '../services/contacts_service.dart';
import '../services/profile_service.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

/// The landing screen: your 1:1 chats and any pending contact requests.
/// Tapping a chat pushes the full chat screen.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.uid, required this.email});

  final String uid;
  final String email;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ProfileService _profiles = ProfileService();
  final ContactsService _contacts = ContactsService();

  @override
  void initState() {
    super.initState();
    // Profiles exist purely so chat bubbles can say who wrote something.
    _profiles.ensureProfile(uid: widget.uid, email: widget.email);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to use KinChat.'),
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
      _toast('Could not start the chat: $e');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          uid: widget.uid,
          room: ChatRoom.private(roomId),
          title: person.safeName,
          names: names,
        ),
      ),
    );
  }

  Future<void> _accept(Profile person) async {
    try {
      await _contacts.accept(widget.uid, person.uid);
      _toast('${person.safeName} added. You can chat now.');
    } catch (e) {
      _toast('Could not accept: $e');
    }
  }

  Future<void> _removeLink(Profile person) async {
    try {
      await _contacts.remove(widget.uid, person.uid);
    } catch (e) {
      _toast('Could not update: $e');
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
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
        builder: (context, membersSnap) {
          if (membersSnap.hasError) {
            return _ErrorText(
              message: 'Could not load the family list.\n\n'
                  '${membersSnap.error}',
            );
          }

          final members = membersSnap.data ?? const <Profile>[];
          final names = <String, String>{
            for (final p in members) p.uid: p.safeName,
          };
          final others =
              members.where((p) => p.uid != widget.uid).toList();

          return StreamBuilder<List<ContactLink>>(
            stream: _contacts.watch(widget.uid),
            builder: (context, linksSnap) {
              if (linksSnap.hasError) {
                return _ErrorText(
                  message: 'Could not load your contacts.\n\n'
                      '${linksSnap.error}',
                );
              }

              final links = {
                for (final l in linksSnap.data ?? const <ContactLink>[])
                  l.uid: l,
              };
              final incoming = others
                  .where((p) =>
                      links[p.uid]?.incomingRequest(widget.uid) == true)
                  .toList();
              final accepted = others
                  .where((p) => links[p.uid]?.accepted == true)
                  .toList();
              final outgoing = others
                  .where((p) =>
                      links[p.uid]?.outgoingRequest(widget.uid) == true)
                   .toList();

              return ListView(
                children: [
                  if (incoming.isNotEmpty) ...[
                    const _SectionHeader(label: 'Requests'),
                    for (final person in incoming)
                      ListTile(
                        leading: CircleAvatar(
                          child: Text(_initials(person.safeName)),
                        ),
                        title: Text(person.safeName),
                        subtitle: const Text('wants to chat'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => _removeLink(person),
                              child: const Text('Decline'),
                            ),
                            FilledButton(
                              onPressed: () => _accept(person),
                              child: const Text('Accept'),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const _SectionHeader(label: 'Chats'),
                  if (accepted.isEmpty)
                    const _Hint('No private chats yet. Add a friend from Settings.')
                  else
                    for (final person in accepted)
                      ListTile(
                        leading: CircleAvatar(
                          child: Text(_initials(person.safeName)),
                        ),
                        title: Text(person.safeName),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openProfile(names, person),
                        onLongPress: () => _confirmRemove(person),
                      ),
                  if (outgoing.isNotEmpty) ...[
                    const _SectionHeader(label: 'Sent'),
                    for (final person in outgoing)
                      ListTile(
                        leading: CircleAvatar(
                          child: Text(_initials(person.safeName)),
                        ),
                        title: Text(person.safeName),
                        subtitle: const Text('Request sent'),
                        trailing: TextButton(
                          onPressed: () => _removeLink(person),
                          child: const Text('Cancel'),
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmRemove(Profile person) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${person.safeName}?'),
        content: const Text(
          'You will no longer be able to message each other until you add '
          'one another again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes == true) await _removeLink(person);
  }

  static String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        message,
        style: const TextStyle(color: Colors.black54),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
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
