import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/profile.dart';
import '../services/chat_service.dart';
import '../services/contacts_service.dart';
import '../services/profile_service.dart';
import '../services/theme_service.dart';
import '../services/wallpaper_service.dart';

/// Personal tweaks: the name others see and the chat background, which is
/// kept only on this phone. Reachable from the home screen's gear icon.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.uid, required this.email});

  final String uid;
  final String email;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ProfileService _profiles = ProfileService();
  final ChatService _chat = ChatService();
  final ContactsService _contacts = ContactsService();
  final TextEditingController _name = TextEditingController();
  String? _wallpaperPath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadWallpaper();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadWallpaper() async {
    final path = await WallpaperService.loadPath();
    if (mounted) setState(() => _wallpaperPath = path);
  }

  Future<void> _pickWallpaper() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 2400,
      imageQuality: 80,
    );
    if (!mounted || file == null) return;
    try {
      final bytes = await file.readAsBytes();
      final path = await WallpaperService.saveBytes(bytes);
      if (mounted) setState(() => _wallpaperPath = path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not set background: $e')),
        );
      }
    }
  }

  Future<void> _removeWallpaper() async {
    await WallpaperService.remove();
    if (mounted) setState(() => _wallpaperPath = null);
  }

  Future<void> _clearChat(ChatRoom room, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear the $label chat?'),
        content: const Text(
          'Every message in this chat will be deleted for everyone. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _chat.clearChat(room);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label chat cleared.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not clear: $e')),
        );
      }
    }
  }

  Future<void> _saveName() async {
    setState(() => _saving = true);
    try {
      await _profiles.updateDisplayName(
        uid: widget.uid,
        name: _name.text,
        email: widget.email,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Name saved.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addFriend() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a friend'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Their exact name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    controller.dispose();
    final wanted = name?.trim() ?? '';
    if (!mounted || wanted.isEmpty) return;
    try {
      final person = await _profiles.findByHandle(wanted);
      if (person == null) {
        _toast('No one here goes by "$wanted".');
        return;
      }
      if (person.uid == widget.uid) {
        _toast("That's you!");
        return;
      }
      await _contacts.request(widget.uid, person.uid);
      if (mounted) _toast('Request sent to ${person.safeName}.');
    } catch (e) {
      _toast('Could not send request: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: StreamBuilder<Profile?>(
        stream: _profiles.watchMyProfile(widget.uid),
        builder: (context, snapshot) {
          final profile = snapshot.data;
          if (profile != null && _name.text.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _name.text.isEmpty) {
                _name.text = profile.safeName;
              }
            });
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _Header(label: 'Your name'),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                maxLength: 60,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name others see',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveName,
                  icon: const Icon(Icons.check),
                  label: const Text('Save'),
                ),
              ),
              const Divider(height: 40),
              const _Header(label: 'Chat background'),
              const SizedBox(height: 8),
              if (_wallpaperPath != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(_wallpaperPath!),
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _pickWallpaper,
                    icon: const Icon(Icons.image_outlined),
                    label:
                        Text(_wallpaperPath == null ? 'Choose an image' : 'Change'),
                  ),
                  if (_wallpaperPath != null) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _removeWallpaper,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Your background lives only on this phone - nobody else can '
                'see it, and it is never uploaded.',
                style: TextStyle(fontSize: 12),
              ),
              const Divider(height: 40),
              const _Header(label: 'Appearance'),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: ThemeService.instance,
                builder: (context, _) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Dark mode'),
                  subtitle: const Text('Cosy on the eyes, especially at night.'),
                  value: ThemeService.instance.darkMode,
                  onChanged: (value) =>
                      ThemeService.instance.setDarkMode(value),
                ),
              ),
              const Divider(height: 40),
              const _Header(label: 'Add a friend'),
              const SizedBox(height: 8),
              const Text(
                'Type the exact name they use in KinChat, then send a request. '
                'They must accept before you can chat.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: _addFriend,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Add a friend'),
                ),
              ),
              const Divider(height: 40),
              const _Header(label: 'Clear chat'),
              const SizedBox(height: 8),
              const Text(
                'Permanently deletes every message in a chat, for everyone. '
                'There is no undo.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              StreamBuilder<List<Profile>>(
                stream: _profiles.watchMembers(),
                builder: (context, snapshot) {
                  final members = snapshot.data ?? const <Profile>[];
                  final others =
                      members.where((p) => p.uid != widget.uid).toList();
                  return Column(
                    children: [
                      for (final person in others)
                        _ClearTile(
                          label: person.safeName,
                          subtitle: 'Your private chat',
                          onClear: () => _clearChat(
                            ChatRoom.private(ProfileService
                                .conversationIdFor(widget.uid, person.uid)),
                            person.safeName,
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }
}

class _ClearTile extends StatelessWidget {
  const _ClearTile({
    required this.label,
    required this.onClear,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.delete_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle!),
      onTap: onClear,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}