/// Data model for a two-player, Slay-the-Spire-style duel.
///
/// The state is pure data: it can be serialized to Firestore, and the rules
/// live in `DuelEngine`. A duel document is stored separately from the chat
/// message that announces it, so messages stay immutable.
class DuelCard {
  const DuelCard({
    required this.id,
    required this.name,
    required this.cost,
    required this.description,
    required this.damage,
    required this.block,
    required this.draw,
    required this.vulnerable,
    required this.kind,
  });

  final String id;
  final String name;
  final int cost;
  final String description;
  final int damage;
  final int block;
  final int draw;
  final int vulnerable;

  /// 'attack' or 'skill'; used only for colouring the card.
  final String kind;
}

const Map<String, DuelCard> duelCards = {
  'strike': DuelCard(
    id: 'strike',
    name: 'Strike',
    cost: 1,
    description: 'Deal 6 damage.',
    damage: 6,
    block: 0,
    draw: 0,
    vulnerable: 0,
    kind: 'attack',
  ),
  'defend': DuelCard(
    id: 'defend',
    name: 'Defend',
    cost: 1,
    description: 'Gain 5 block.',
    damage: 0,
    block: 5,
    draw: 0,
    vulnerable: 0,
    kind: 'skill',
  ),
  'bash': DuelCard(
    id: 'bash',
    name: 'Bash',
    cost: 2,
    description: 'Deal 8 damage. Apply 2 Vulnerable.',
    damage: 8,
    block: 0,
    draw: 0,
    vulnerable: 2,
    kind: 'attack',
  ),
  'quick_jab': DuelCard(
    id: 'quick_jab',
    name: 'Quick Jab',
    cost: 0,
    description: 'Deal 3 damage.',
    damage: 3,
    block: 0,
    draw: 0,
    vulnerable: 0,
    kind: 'attack',
  ),
  'iron_wave': DuelCard(
    id: 'iron_wave',
    name: 'Iron Wave',
    cost: 1,
    description: 'Deal 5 damage. Gain 5 block.',
    damage: 5,
    block: 5,
    draw: 0,
    vulnerable: 0,
    kind: 'attack',
  ),
  'heavy_blow': DuelCard(
    id: 'heavy_blow',
    name: 'Heavy Blow',
    cost: 2,
    description: 'Deal 14 damage.',
    damage: 14,
    block: 0,
    draw: 0,
    vulnerable: 0,
    kind: 'attack',
  ),
  'shrug_it_off': DuelCard(
    id: 'shrug_it_off',
    name: 'Shrug It Off',
    cost: 1,
    description: 'Gain 8 block. Draw 1 card.',
    damage: 0,
    block: 8,
    draw: 1,
    vulnerable: 0,
    kind: 'skill',
  ),
  'pommel_strike': DuelCard(
    id: 'pommel_strike',
    name: 'Pommel Strike',
    cost: 1,
    description: 'Deal 9 damage. Draw 1 card.',
    damage: 9,
    block: 0,
    draw: 1,
    vulnerable: 0,
    kind: 'attack',
  ),
};

/// Five Strikes, four Defends, and one Bash.
List<String> duelStarterDeck() => <String>[
  'strike',
  'strike',
  'strike',
  'strike',
  'strike',
  'defend',
  'defend',
  'defend',
  'defend',
  'bash',
];

class DuelLogEntry {
  const DuelLogEntry({required this.uid, required this.text});

  /// Empty for system messages.
  final String uid;
  final String text;

  Map<String, dynamic> toMap() => {'uid': uid, 'text': text};

  factory DuelLogEntry.fromMap(Map<String, dynamic> map) => DuelLogEntry(
    uid: map['uid'] as String? ?? '',
    text: map['text'] as String? ?? '',
  );
}

class DuelPlayer {
  const DuelPlayer({
    required this.uid,
    required this.hp,
    required this.maxHp,
    required this.block,
    required this.energy,
    required this.maxEnergy,
    required this.vulnerable,
    required this.hand,
    required this.drawPile,
    required this.discardPile,
  });

  final String uid;
  final int hp;
  final int maxHp;
  final int block;
  final int energy;
  final int maxEnergy;
  final int vulnerable;
  final List<String> hand;
  final List<String> drawPile;
  final List<String> discardPile;

  bool get isDead => hp <= 0;
  int get handCount => hand.length;

  DuelPlayer copyWith({
    int? hp,
    int? maxHp,
    int? block,
    int? energy,
    int? maxEnergy,
    int? vulnerable,
    List<String>? hand,
    List<String>? drawPile,
    List<String>? discardPile,
  }) => DuelPlayer(
    uid: uid,
    hp: hp ?? this.hp,
    maxHp: maxHp ?? this.maxHp,
    block: block ?? this.block,
    energy: energy ?? this.energy,
    maxEnergy: maxEnergy ?? this.maxEnergy,
    vulnerable: vulnerable ?? this.vulnerable,
    hand: hand ?? this.hand,
    drawPile: drawPile ?? this.drawPile,
    discardPile: discardPile ?? this.discardPile,
  );

  Map<String, dynamic> toMap() => {
    'hp': hp,
    'maxHp': maxHp,
    'block': block,
    'energy': energy,
    'maxEnergy': maxEnergy,
    'vulnerable': vulnerable,
    'hand': hand,
    'drawPile': drawPile,
    'discardPile': discardPile,
  };

  factory DuelPlayer.fromMap(String uid, Map<String, dynamic> map) =>
      DuelPlayer(
        uid: uid,
        hp: (map['hp'] as num?)?.toInt() ?? 0,
        maxHp: (map['maxHp'] as num?)?.toInt() ?? 50,
        block: (map['block'] as num?)?.toInt() ?? 0,
        energy: (map['energy'] as num?)?.toInt() ?? 0,
        maxEnergy: (map['maxEnergy'] as num?)?.toInt() ?? 3,
        vulnerable: (map['vulnerable'] as num?)?.toInt() ?? 0,
        hand: _stringList(map['hand']),
        drawPile: _stringList(map['drawPile']),
        discardPile: _stringList(map['discardPile']),
      );
}

class DuelState {
  const DuelState({
    required this.gameId,
    required this.participants,
    required this.createdBy,
    required this.status,
    required this.winner,
    required this.turn,
    required this.turnCount,
    required this.shuffleSeed,
    required this.players,
    required this.log,
  });

  final String gameId;
  final List<String> participants;
  final String createdBy;

  /// 'active' or 'finished'.
  final String status;

  /// Empty while the duel is active.
  final String winner;
  final String turn;
  final int turnCount;
  final int shuffleSeed;
  final Map<String, DuelPlayer> players;
  final List<DuelLogEntry> log;

  bool get isActive => status == 'active';
  bool get isFinished => status == 'finished';
  int get round => (turnCount ~/ 2) + 1;

  DuelPlayer? player(String uid) => players[uid];

  String otherUid(String uid) {
    for (final participant in participants) {
      if (participant != uid) return participant;
    }
    return '';
  }

  DuelState copyWith({
    String? status,
    String? winner,
    String? turn,
    int? turnCount,
    int? shuffleSeed,
    Map<String, DuelPlayer>? players,
    List<DuelLogEntry>? log,
  }) => DuelState(
    gameId: gameId,
    participants: participants,
    createdBy: createdBy,
    status: status ?? this.status,
    winner: winner ?? this.winner,
    turn: turn ?? this.turn,
    turnCount: turnCount ?? this.turnCount,
    shuffleSeed: shuffleSeed ?? this.shuffleSeed,
    players: players ?? this.players,
    log: log ?? this.log,
  );

  Map<String, dynamic> toMap() => {
    'participants': participants,
    'createdBy': createdBy,
    'status': status,
    'winner': winner,
    'turn': turn,
    'turnCount': turnCount,
    'shuffleSeed': shuffleSeed,
    'players': players.map((key, value) => MapEntry(key, value.toMap())),
    'log': log.map((entry) => entry.toMap()).toList(growable: false),
  };

  factory DuelState.fromMap(String gameId, Map<String, dynamic> map) {
    final rawPlayers = map['players'];
    final players = <String, DuelPlayer>{};
    if (rawPlayers is Map) {
      rawPlayers.forEach((key, value) {
        if (key is String && value is Map) {
          players[key] = DuelPlayer.fromMap(
            key,
            Map<String, dynamic>.from(value),
          );
        }
      });
    }

    final rawLog = map['log'];
    final log = <DuelLogEntry>[];
    if (rawLog is List) {
      for (final entry in rawLog) {
        if (entry is Map) {
          log.add(DuelLogEntry.fromMap(Map<String, dynamic>.from(entry)));
        }
      }
    }

    return DuelState(
      gameId: gameId,
      participants: _stringList(map['participants']),
      createdBy: map['createdBy'] as String? ?? '',
      status: map['status'] as String? ?? 'active',
      winner: map['winner'] as String? ?? '',
      turn: map['turn'] as String? ?? '',
      turnCount: (map['turnCount'] as num?)?.toInt() ?? 1,
      shuffleSeed: (map['shuffleSeed'] as num?)?.toInt() ?? 0,
      players: players,
      log: log,
    );
  }
}

List<String> _stringList(Object? value) {
  if (value is List) return value.whereType<String>().toList(growable: false);
  return const <String>[];
}
