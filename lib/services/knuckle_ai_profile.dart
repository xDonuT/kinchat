import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum KnuckleAiDifficulty {
  easy('Easy', 'One-step thinking. Relaxed and beatable.'),
  normal('Normal', 'Two-step thinking. Balanced.'),
  hard('Hard', 'Two-step thinking plus capped learning.');

  const KnuckleAiDifficulty(this.label, this.description);

  final String label;
  final String description;

  static KnuckleAiDifficulty fromIndex(int? index) {
    if (index == null || index < 0 || index >= values.length) return normal;
    return values[index];
  }
}

class KnuckleAiProfile {
  const KnuckleAiProfile({
    this.columnCounts = const <int>[0, 0, 0],
    this.games = 0,
  });

  static const int maxBiasPercent = 15;

  final List<int> columnCounts;
  final int games;

  int get totalPlacements =>
      columnCounts.fold(0, (total, count) => total + count);

  double columnBias(int column) {
    if (column < 0 || column >= columnCounts.length) return 0;
    final total = totalPlacements;
    if (total < 6) return 0;

    final share = columnCounts[column] / total;
    final edge = (share - 1 / 3) / (2 / 3);
    final cap = maxBiasPercent / 100;
    final bias = edge * cap;
    if (bias <= 0) return 0;
    return bias > cap ? cap : bias;
  }

  KnuckleAiProfile decayed() {
    return KnuckleAiProfile(
      columnCounts: [
        for (final count in columnCounts) (count * 9) ~/ 10,
      ],
      games: games + 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'columns': columnCounts,
    'games': games,
  };

  factory KnuckleAiProfile.fromJson(Map<String, dynamic> json) {
    final raw = json['columns'];
    final counts = <int>[0, 0, 0];
    if (raw is List) {
      for (var index = 0; index < counts.length && index < raw.length; index++) {
        final value = raw[index];
        if (value is! num) continue;
        final parsed = value.toInt();
        counts[index] = parsed < 0 ? 0 : (parsed > 500 ? 500 : parsed);
      }
    }
    return KnuckleAiProfile(
      columnCounts: counts,
      games: (json['games'] as num?)?.toInt() ?? 0,
    );
  }
}

class KnuckleAiProfileStore {
  static const String _profileKey = 'knuckle_ai_profile_v1';
  static const String _difficultyKey = 'knuckle_ai_difficulty_v1';

  static Future<KnuckleAiProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey);
    if (raw == null || raw.isEmpty) return const KnuckleAiProfile();

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const KnuckleAiProfile();
      return KnuckleAiProfile.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const KnuckleAiProfile();
    }
  }

  static Future<void> recordPlacement(int column) async {
    if (column < 0 || column >= 3) return;
    final profile = await load();
    final counts = List<int>.of(profile.columnCounts);
    while (counts.length < 3) {
      counts.add(0);
    }
    final next = counts[column] + 1;
    counts[column] = next > 500 ? 500 : next;
    await _save(KnuckleAiProfile(columnCounts: counts, games: profile.games));
  }

  static Future<void> recordResult() async {
    final profile = await load();
    await _save(profile.decayed());
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileKey);
  }

  static Future<KnuckleAiDifficulty> loadDifficulty() async {
    final prefs = await SharedPreferences.getInstance();
    return KnuckleAiDifficulty.fromIndex(prefs.getInt(_difficultyKey));
  }

  static Future<void> saveDifficulty(KnuckleAiDifficulty difficulty) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_difficultyKey, difficulty.index);
  }

  static Future<void> _save(KnuckleAiProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }
}
