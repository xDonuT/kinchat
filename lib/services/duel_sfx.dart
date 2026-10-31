import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class DuelSfx {
  DuelSfx._();

  static final DuelSfx instance = DuelSfx._();

  final AudioPlayer _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

  bool _enabled = true;

  bool get enabled => _enabled;

  void setEnabled(bool value) {
    _enabled = value;
  }

  Future<void> play(String name) async {
    if (!_enabled) return;
    try {
      await _player.stop();
      await _player.play(AssetSource('sfx/$name.wav'), volume: 0.35);
    } catch (error) {
      debugPrint('Duel sound failed: $error');
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {
      // The player may already be gone when the screen is closed.
    }
  }
}
