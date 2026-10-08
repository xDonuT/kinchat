import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/profile.dart';
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
              const SizedBox(height: 12),
            ],
          );
        },
      ),
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