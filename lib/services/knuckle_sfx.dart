import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class KnuckleSfx {
  KnuckleSfx._();

  static final KnuckleSfx instance = KnuckleSfx._();

  final AudioPlayer _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

  static const Map<String, double> _volumes = {
    'roll': 0.4,
    'place': 0.55,
    'hit': 0.5,
    'win': 0.45,
    'lose': 0.45,
  };

  bool _enabled = true;

  bool get enabled => _enabled;

  void setEnabled(bool value) {
    _enabled = value;
  }

  Future<void> play(String name) async {
    if (!_enabled) return;
    try {
      await _player.stop();
      await _player.play(
        AssetSource('sfx/$name.wav'),
        volume: _volumes[name] ?? 0.4,
      );
    } catch (error) {
      debugPrint('Knuckle sound failed: $error');
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }
}
