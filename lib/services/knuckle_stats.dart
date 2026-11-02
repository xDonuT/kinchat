import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class KnuckleStatLine {
  const KnuckleStatLine({
    required this.id,
    required this.name,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
  });

  final String id;
  final String name;
  final int wins;
  final int losses;
  final int draws;

  int get played => wins + losses + draws;
  int get points => wins * 3 + draws;
  double get winRate => played == 0 ? 0 : wins / played;

  KnuckleStatLine copyWith({
    String? name,
    int? wins,
    int? losses,
    int? draws,
  }) {
    return KnuckleStatLine(
      id: id,
      name: name ?? this.name,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
      draws: draws ?? this.draws,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'wins': wins,
    'losses': losses,
    'draws': draws,
  };

  factory KnuckleStatLine.fromJson(String id, Map<String, dynamic> json) {
    return KnuckleStatLine(
      id: id,
      name: json['name'] as String? ?? 'Opponent',
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      draws: (json['draws'] as num?)?.toInt() ?? 0,
    );
  }
}

class KnuckleStats {
  KnuckleStats([Map<String, KnuckleStatLine>? opponents])
    : opponents = Map<String, KnuckleStatLine>.unmodifiable(
        opponents ?? const <String, KnuckleStatLine>{},
      );

  final Map<String, KnuckleStatLine> opponents;

  int get wins =>
      opponents.values.fold(0, (total, line) => total + line.wins);
  int get losses =>
      opponents.values.fold(0, (total, line) => total + line.losses);
  int get draws =>
      opponents.values.fold(0, (total, line) => total + line.draws);
  int get played => wins + losses + draws;

  KnuckleStatLine? forOpponent(String? id) {
    if (id == null) return null;
    return opponents[id];
  }

  List<KnuckleStatLine> get leaderboard {
    final lines = opponents.values.toList();
    lines.sort((a, b) {
      final byPoints = b.points.compareTo(a.points);
      if (byPoints != 0) return byPoints;
      final byWins = b.wins.compareTo(a.wins);
      if (byWins != 0) return byWins;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return lines;
  }
}

class KnuckleStatsStore {
  static const String _prefsKey = 'knuckle_stats_v1';

  static Future<KnuckleStats> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return KnuckleStats();

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return KnuckleStats();
      final rawOpponents = decoded['opponents'];
      if (rawOpponents is! Map) return KnuckleStats();

      final opponents = <String, KnuckleStatLine>{};
      rawOpponents.forEach((key, value) {
        if (value is! Map) return;
        final id = key.toString();
        opponents[id] = KnuckleStatLine.fromJson(
          id,
          Map<String, dynamic>.from(value),
        );
      });
      return KnuckleStats(opponents);
    } catch (_) {
      return KnuckleStats();
    }
  }

  static Future<KnuckleStats> record({
    required String myUid,
    required String opponentId,
    required String opponentName,
    required String winner,
  }) async {
    final current = await load();
    if (winner.isEmpty) return current;

    final existing =
        current.opponents[opponentId] ??
        KnuckleStatLine(id: opponentId, name: opponentName);
    final name = opponentName.trim().isEmpty ? existing.name : opponentName;
    final updated = existing.copyWith(
      name: name,
      wins: winner == myUid ? existing.wins + 1 : existing.wins,
      losses: winner != myUid && winner != 'draw'
          ? existing.losses + 1
          : existing.losses,
      draws: winner == 'draw' ? existing.draws + 1 : existing.draws,
    );

    final opponents = Map<String, KnuckleStatLine>.of(current.opponents)
      ..[opponentId] = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'opponents': {
          for (final entry in opponents.entries)
            entry.key: entry.value.toJson(),
        },
      }),
    );
    return KnuckleStats(opponents);
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
