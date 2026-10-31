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
    this.poison = 0,
    this.focus = 0,
    this.focusMultiplier = 0,
    this.cleanse = 0,
    this.heal = 0,
  });

  final String id;
  final String name;
  final int cost;
  final String description;
  final int damage;
  final int block;
  final int draw;
  final int vulnerable;
  final int poison;
  final int focus;
  final int focusMultiplier;
  final int cleanse;
  final int heal;

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
  'poison_stab': DuelCard(
    id: 'poison_stab',
    name: 'Poison Stab',
    cost: 1,
    description: 'Deal 3 damage. Apply 3 Poison.',
    damage: 3,
    block: 0,
    draw: 0,
    vulnerable: 0,
    poison: 3,
    kind: 'attack',
  ),
  'deadly_poison': DuelCard(
    id: 'deadly_poison',
    name: 'Deadly Poison',
    cost: 1,
    description: 'Apply 4 Poison. Poison ignores block.',
    damage: 0,
    block: 0,
    draw: 0,
    vulnerable: 0,
    poison: 4,
    kind: 'skill',
  ),
  'zap': DuelCard(
    id: 'zap',
    name: 'Zap',
    cost: 0,
    description: 'Gain 1 Focus.',
    damage: 0,
    block: 0,
    draw: 0,
    vulnerable: 0,
    focus: 1,
    kind: 'skill',
  ),
  'arcane_bolt': DuelCard(
    id: 'arcane_bolt',
    name: 'Arcane Bolt',
    cost: 1,
    description: 'Deal 4 damage, plus 2 per Focus.',
    damage: 4,
    block: 0,
    draw: 0,
    vulnerable: 0,
    focusMultiplier: 2,
    kind: 'attack',
  ),
  'mana_shield': DuelCard(
    id: 'mana_shield',
    name: 'Mana Shield',
    cost: 1,
    description: 'Gain 5 block and 1 Focus.',
    damage: 0,
    block: 5,
    draw: 0,
    vulnerable: 0,
    focus: 1,
    kind: 'skill',
  ),
  'fireball': DuelCard(
    id: 'fireball',
    name: 'Fireball',
    cost: 2,
    description: 'Deal 6 damage, plus 2 per Focus.',
    damage: 6,
    block: 0,
    draw: 0,
    vulnerable: 0,
    focusMultiplier: 2,
    kind: 'attack',
  ),
  'cleanse': DuelCard(
    id: 'cleanse',
    name: 'Cleanse',
    cost: 1,
    description: 'Remove Poison and Vulnerable from yourself.',
    damage: 0,
    block: 0,
    draw: 0,
    vulnerable: 0,
    poison: 0,
    focus: 0,
    focusMultiplier: 0,
    cleanse: 1,
    kind: 'skill',
  ),
  'rest': DuelCard(
    id: 'rest',
    name: 'Rest',
    cost: 1,
    description: 'Heal 4 HP.',
    damage: 0,
    block: 0,
    draw: 0,
    vulnerable: 0,
    poison: 0,
    focus: 0,
    focusMultiplier: 0,
    cleanse: 0,
    heal: 4,
    kind: 'skill',
  ),
  'strike_plus': DuelCard(
    id: 'strike_plus',
    name: 'Strike+',
    cost: 2,
    description: 'Deal 10 damage.',
    damage: 10,
    block: 0,
    draw: 0,
    vulnerable: 0,
    kind: 'attack',
  ),
  'defend_plus': DuelCard(
    id: 'defend_plus',
    name: 'Defend+',
    cost: 2,
    description: 'Gain 8 block.',
    damage: 0,
    block: 8,
    draw: 0,
    vulnerable: 0,
    kind: 'skill',
  ),
  'bash_plus': DuelCard(
    id: 'bash_plus',
    name: 'Bash+',
    cost: 3,
    description: 'Deal 12 damage. Apply 3 Vulnerable.',
    damage: 12,
    block: 0,
    draw: 0,
    vulnerable: 3,
    kind: 'attack',
  ),
  'quick_jab_plus': DuelCard(
    id: 'quick_jab_plus',
    name: 'Quick Jab+',
    cost: 1,
    description: 'Deal 5 damage.',
    damage: 5,
    block: 0,
    draw: 0,
    vulnerable: 0,
    kind: 'attack',
  ),
  'poison_stab_plus': DuelCard(
    id: 'poison_stab_plus',
    name: 'Poison Stab+',
    cost: 2,
    description: 'Deal 5 damage. Apply 4 Poison.',
    damage: 5,
    block: 0,
    draw: 0,
    vulnerable: 0,
    poison: 4,
    kind: 'attack',
  ),
  'deadly_poison_plus': DuelCard(
    id: 'deadly_poison_plus',
    name: 'Deadly Poison+',
    cost: 2,
    description: 'Apply 6 Poison. Poison ignores block.',
    damage: 0,
    block: 0,
    draw: 0,
    vulnerable: 0,
    poison: 6,
    kind: 'skill',
  ),
  'zap_plus': DuelCard(
    id: 'zap_plus',
    name: 'Zap+',
    cost: 1,
    description: 'Gain 2 Focus.',
    damage: 0,
    block: 0,
    draw: 0,
    vulnerable: 0,
    focus: 2,
    kind: 'skill',
  ),
  'arcane_bolt_plus': DuelCard(
    id: 'arcane_bolt_plus',
    name: 'Arcane Bolt+',
    cost: 2,
    description: 'Deal 6 damage, plus 3 per Focus.',
    damage: 6,
    block: 0,
    draw: 0,
    vulnerable: 0,
    focusMultiplier: 3,
    kind: 'attack',
  ),
  'fireball_plus': DuelCard(
    id: 'fireball_plus',
    name: 'Fireball+',
    cost: 3,
    description: 'Deal 10 damage, plus 3 per Focus.',
    damage: 10,
    block: 0,
    draw: 0,
    vulnerable: 0,
    focusMultiplier: 3,
    kind: 'attack',
  ),
};

List<String> rewardDraftOptions({required String classId}) {
  switch (classId) {
    case 'ninja':
      return const <String>['rest', 'quick_jab_plus', 'poison_stab_plus'];
    case 'wizard':
      return const <String>['rest', 'zap_plus', 'arcane_bolt_plus'];
    case 'knight':
    default:
      return const <String>['rest', 'strike_plus', 'defend_plus'];
  }
}

const String defaultDuelClassId = 'knight';

class DuelClass {
  const DuelClass({
    required this.id,
    required this.name,
    required this.maxHp,
    required this.maxEnergy,
    required this.description,
  });

  final String id;
  final String name;
  final int maxHp;
  final int maxEnergy;
  final String description;
}

const Map<String, DuelClass> duelClasses = {
  'knight': DuelClass(
    id: 'knight',
    name: 'Knight',
    maxHp: 50,
    maxEnergy: 3,
    description: 'High HP. Block and Vulnerable.',
  ),
  'ninja': DuelClass(
    id: 'ninja',
    name: 'Ninja',
    maxHp: 42,
    maxEnergy: 3,
    description: 'Apply Poison and chip away. Poison ignores block.',
  ),
  'wizard': DuelClass(
    id: 'wizard',
    name: 'Wizard',
    maxHp: 44,
    maxEnergy: 3,
    description: 'Gain Focus, then empower Arcane Bolt and Fireball.',
  ),
};

List<String> duelStarterDeck({String classId = defaultDuelClassId}) {
  switch (classId) {
    case 'ninja':
      return const <String>[
        'strike',
        'strike',
        'strike',
        'strike',
        'defend',
        'defend',
        'quick_jab',
        'pommel_strike',
        'poison_stab',
        'deadly_poison',
      ];
    case 'wizard':
      return const <String>[
        'strike',
        'strike',
        'strike',
        'strike',
        'defend',
        'defend',
        'zap',
        'arcane_bolt',
        'mana_shield',
        'fireball',
      ];
    case 'knight':
    default:
      return const <String>[
        'strike',
        'strike',
        'strike',
        'strike',
        'defend',
        'defend',
        'bash',
        'iron_wave',
        'heavy_blow',
        'shrug_it_off',
      ];
  }
}

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
    this.classId = defaultDuelClassId,
    required this.hp,
    required this.maxHp,
    required this.block,
    required this.energy,
    required this.maxEnergy,
    required this.vulnerable,
    this.poison = 0,
    this.focus = 0,
    this.ready = false,
    required this.hand,
    required this.drawPile,
    required this.discardPile,
  });

  final String uid;
  final String classId;
  final int hp;
  final int maxHp;
  final int block;
  final int energy;
  final int maxEnergy;
  final int vulnerable;
  final int poison;
  final int focus;
  final bool ready;
  final List<String> hand;
  final List<String> drawPile;
  final List<String> discardPile;

  bool get isDead => hp <= 0;
  int get handCount => hand.length;

  DuelPlayer copyWith({
    String? classId,
    int? hp,
    int? maxHp,
    int? block,
    int? energy,
    int? maxEnergy,
    int? vulnerable,
    int? poison,
    int? focus,
    bool? ready,
    List<String>? hand,
    List<String>? drawPile,
    List<String>? discardPile,
  }) => DuelPlayer(
    uid: uid,
    classId: classId ?? this.classId,
    hp: hp ?? this.hp,
    maxHp: maxHp ?? this.maxHp,
    block: block ?? this.block,
    energy: energy ?? this.energy,
    maxEnergy: maxEnergy ?? this.maxEnergy,
    vulnerable: vulnerable ?? this.vulnerable,
    poison: poison ?? this.poison,
    focus: focus ?? this.focus,
    ready: ready ?? this.ready,
    hand: hand ?? this.hand,
    drawPile: drawPile ?? this.drawPile,
    discardPile: discardPile ?? this.discardPile,
  );

  Map<String, dynamic> toMap() => {
    'classId': classId,
    'hp': hp,
    'maxHp': maxHp,
    'block': block,
    'energy': energy,
    'maxEnergy': maxEnergy,
    'vulnerable': vulnerable,
    'poison': poison,
    'focus': focus,
    'ready': ready,
    'hand': hand,
    'drawPile': drawPile,
    'discardPile': discardPile,
  };

  factory DuelPlayer.fromMap(String uid, Map<String, dynamic> map) =>
      DuelPlayer(
        uid: uid,
        classId: map['classId'] as String? ?? defaultDuelClassId,
        hp: (map['hp'] as num?)?.toInt() ?? 0,
        maxHp: (map['maxHp'] as num?)?.toInt() ?? 50,
        block: (map['block'] as num?)?.toInt() ?? 0,
        energy: (map['energy'] as num?)?.toInt() ?? 0,
        maxEnergy: (map['maxEnergy'] as num?)?.toInt() ?? 3,
        vulnerable: (map['vulnerable'] as num?)?.toInt() ?? 0,
        poison: (map['poison'] as num?)?.toInt() ?? 0,
        focus: (map['focus'] as num?)?.toInt() ?? 0,
        ready: map['ready'] as bool? ?? false,
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
    required this.draftRound,
    required this.draftPicks,
  });

  final String gameId;
  final List<String> participants;
  final String createdBy;

  /// 'lobby', 'active', or 'finished'.
  final String status;

  /// Empty while the duel is active.
  final String winner;
  final String turn;
  final int turnCount;
  final int shuffleSeed;
  final Map<String, DuelPlayer> players;
  final List<DuelLogEntry> log;
  final int draftRound;
  final Map<String, String> draftPicks;

  bool get isLobby => status == 'lobby';
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
    int? draftRound,
    Map<String, String>? draftPicks,
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
    draftRound: draftRound ?? this.draftRound,
    draftPicks: draftPicks ?? this.draftPicks,
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
    'draftRound': draftRound,
    'draftPicks': draftPicks,
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
      draftRound: (map['draftRound'] as num?)?.toInt() ?? 0,
      draftPicks: _stringMap(map['draftPicks']),
    );
  }
}

List<String> _stringList(Object? value) {
  if (value is List) return value.whereType<String>().toList(growable: false);
  return const <String>[];
}

Map<String, String> _stringMap(Object? value) {
  final map = <String, String>{};
  if (value is Map) {
    value.forEach((key, val) {
      if (key is String && val is String) map[key] = val;
    });
  }
  return map;
}
