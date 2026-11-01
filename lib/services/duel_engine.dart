import 'dart:math';

import '../models/duel.dart';

class DuelException implements Exception {
  const DuelException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Pure rules for a two-player duel. No Flutter or Firestore code lives here,
/// which keeps the whole game testable without a device.
class DuelEngine {
  const DuelEngine();

  static const int startingHp = 50;
  static const int maxEnergy = 3;
  static const int handSize = 5;
  static const int maxHandSize = 10;
  static const int maxLogEntries = 40;

  DuelState create({
    required String gameId,
    required String createdBy,
    required String opponentUid,
    String createdByClass = defaultDuelClassId,
    String opponentClass = defaultDuelClassId,
    String? firstTurnUid,
    int? seed,
    bool lobby = false,
  }) {
    if (createdBy == opponentUid) {
      throw const DuelException('Pick another player.');
    }
    final first = firstTurnUid ?? createdBy;
    if (first != createdBy && first != opponentUid) {
      throw const DuelException('Invalid first player.');
    }

    final creatorClass = _classFor(createdByClass);
    final rivalClass = _classFor(opponentClass);
    final shuffleSeed = seed ?? DateTime.now().microsecondsSinceEpoch;
    final rng = Random(shuffleSeed);
    final players = <String, DuelPlayer>{
      createdBy: _freshPlayer(createdBy, creatorClass, rng),
      opponentUid: _freshPlayer(opponentUid, rivalClass, rng),
    };

    if (lobby) {
      return DuelState(
        gameId: gameId,
        participants: [createdBy, opponentUid],
        createdBy: createdBy,
        status: 'lobby',
        winner: '',
        turn: first,
        turnCount: 1,
        shuffleSeed: shuffleSeed + 1,
        players: players,
        log: [
          const DuelLogEntry(
            uid: '',
            text: 'Duel lobby opened. Choose your class and ready up.',
          ),
        ],
      );
    }

    var state = DuelState(
      gameId: gameId,
      participants: [createdBy, opponentUid],
      createdBy: createdBy,
      status: 'active',
      winner: '',
      turn: first,
      turnCount: 1,
      shuffleSeed: shuffleSeed + 1,
      players: players,
      log: [
        DuelLogEntry(
          uid: '',
          text: 'Duel started: ${creatorClass.name} vs ${rivalClass.name}.',
        ),
      ],
    );

    state = _startTurn(state, first);
    return state;
  }

  DuelState chooseClass(
    DuelState state, {
    required String uid,
    required String classId,
  }) {
    if (!state.isLobby) {
      throw const DuelException('This duel has already started.');
    }
    if (!state.participants.contains(uid)) {
      throw const DuelException('Player not found.');
    }
    final duelClass = duelClasses[classId];
    if (duelClass == null) throw const DuelException('Unknown class.');

    final player = state.players[uid];
    if (player == null) throw const DuelException('Player not found.');
    final players = Map<String, DuelPlayer>.of(state.players);
    players[uid] = player.copyWith(classId: duelClass.id, ready: false);

    return state.copyWith(
      players: players,
      log: _appendLog(
        state.log,
        DuelLogEntry(uid: uid, text: 'chose ${duelClass.name}.'),
      ),
    );
  }

  DuelState setReady(
    DuelState state, {
    required String uid,
    required bool ready,
  }) {
    if (!state.isLobby) return state;
    final player = state.players[uid];
    if (player == null) throw const DuelException('Player not found.');

    final players = Map<String, DuelPlayer>.of(state.players);
    players[uid] = player.copyWith(ready: ready);
    var next = state.copyWith(
      players: players,
      log: _appendLog(
        state.log,
        DuelLogEntry(uid: uid, text: ready ? 'is ready.' : 'is not ready.'),
      ),
    );

    if (players.values.every((participant) => participant.ready)) {
      next = _startFromLobby(next);
    }
    return next;
  }

  DuelState restart(DuelState state, {required String uid, int? seed}) {
    if (!state.participants.contains(uid)) {
      throw const DuelException('Player not found.');
    }
    final other = state.participants.firstWhere(
      (participant) => participant != state.createdBy,
      orElse: () => '',
    );
    if (other.isEmpty) throw const DuelException('Opponent not found.');
    return create(
      gameId: state.gameId,
      createdBy: state.createdBy,
      opponentUid: other,
      createdByClass:
          state.players[state.createdBy]?.classId ?? defaultDuelClassId,
      opponentClass: state.players[other]?.classId ?? defaultDuelClassId,
      firstTurnUid: uid,
      seed: seed,
      lobby: true,
    );
  }

  DuelState playCard(
    DuelState state, {
    required String uid,
    required int handIndex,
  }) {
    _requireActive(state);
    if (state.turn != uid) {
      throw const DuelException('It is not your turn.');
    }

    final player = state.players[uid];
    if (player == null) throw const DuelException('Player not found.');
    if (handIndex < 0 || handIndex >= player.hand.length) {
      throw const DuelException('Card not found.');
    }

    final cardId = player.hand[handIndex];
    final card = duelCards[cardId];
    if (card == null) throw const DuelException('Unknown card.');
    if (player.energy < card.cost) {
      throw const DuelException('Not enough energy.');
    }

    final hand = List<String>.of(player.hand)..removeAt(handIndex);
    final discardPile = List<String>.of(player.discardPile)..add(cardId);
    var updatedPlayer = player.copyWith(
      hand: hand,
      discardPile: discardPile,
      energy: player.energy - card.cost,
    );

    final players = Map<String, DuelPlayer>.of(state.players);
    players[uid] = updatedPlayer;

    final targetUid = state.otherUid(uid);
    var target = players[targetUid];
    if (target == null) throw const DuelException('Opponent not found.');

    final details = <String>[];

    final focusDamage = card.focusMultiplier * updatedPlayer.focus;
    if (card.damage > 0 || focusDamage > 0) {
      final rawDamage = card.damage + focusDamage;
      final damage = _damageAfterVulnerable(rawDamage, target.vulnerable);
      final absorbed = min(target.block, damage);
      final hpLoss = damage - absorbed;
      target = target.copyWith(
        block: target.block - absorbed,
        hp: max(0, target.hp - hpLoss),
      );
      players[targetUid] = target;
      details.add('$damage damage');
    }

    if (card.block > 0) {
      updatedPlayer = updatedPlayer.copyWith(
        block: updatedPlayer.block + card.block,
      );
      players[uid] = updatedPlayer;
      details.add('${card.block} block');
    }

    if (card.vulnerable > 0) {
      target = target.copyWith(vulnerable: target.vulnerable + card.vulnerable);
      players[targetUid] = target;
      details.add('${card.vulnerable} vulnerable');
    }

    if (card.poison > 0) {
      target = target.copyWith(poison: target.poison + card.poison);
      players[targetUid] = target;
      details.add('${card.poison} poison');
    }

    if (card.focus > 0) {
      updatedPlayer = updatedPlayer.copyWith(
        focus: updatedPlayer.focus + card.focus,
      );
      players[uid] = updatedPlayer;
      details.add('${card.focus} focus');
    }

    final suffix = details.isEmpty ? '' : ' (${details.join(', ')})';
    var next = state.copyWith(
      players: players,
      log: _appendLog(
        state.log,
        DuelLogEntry(uid: uid, text: 'plays ${card.name}$suffix.'),
      ),
    );

    if (target.hp <= 0) {
      return next.copyWith(
        status: 'finished',
        winner: uid,
        log: _appendLog(
          next.log,
          DuelLogEntry(uid: uid, text: 'wins the duel!'),
        ),
      );
    }

    if (card.draw > 0) {
      next = _drawCards(next, uid, card.draw);
    }

    return next;
  }

  DuelState endTurn(DuelState state, {required String uid}) {
    _requireActive(state);
    if (state.turn != uid) {
      throw const DuelException('It is not your turn.');
    }

    final player = state.players[uid];
    if (player == null) throw const DuelException('Player not found.');

    final discardPile = List<String>.of(player.discardPile)
      ..addAll(player.hand);
    final updated = player.copyWith(
      hand: const [],
      discardPile: discardPile,
      vulnerable: max(0, player.vulnerable - 1),
    );

    final players = Map<String, DuelPlayer>.of(state.players);
    players[uid] = updated;

    final nextUid = state.otherUid(uid);
    var next = state.copyWith(
      players: players,
      turn: nextUid,
      turnCount: state.turnCount + 1,
      log: _appendLog(
        state.log,
        DuelLogEntry(uid: uid, text: 'ends their turn.'),
      ),
    );

    next = _startTurn(next, nextUid);
    return next;
  }

  DuelState _startFromLobby(DuelState state) {
    if (!state.isLobby) return state;
    if (!state.players.values.every((player) => player.ready)) return state;

    final first = state.turn;
    final rng = Random(state.shuffleSeed);
    final players = <String, DuelPlayer>{
      for (final uid in state.participants)
        uid: _freshPlayer(
          uid,
          _classFor(state.players[uid]?.classId ?? defaultDuelClassId),
          rng,
        ),
    };
    final creatorClass = _classFor(
      players[state.createdBy]?.classId ?? defaultDuelClassId,
    );
    final rivalClass = _classFor(
      players[state.otherUid(state.createdBy)]?.classId ?? defaultDuelClassId,
    );

    var next = DuelState(
      gameId: state.gameId,
      participants: state.participants,
      createdBy: state.createdBy,
      status: 'active',
      winner: '',
      turn: first,
      turnCount: 1,
      shuffleSeed: state.shuffleSeed + 1,
      players: players,
      log: [
        DuelLogEntry(
          uid: '',
          text: 'Duel started: ${creatorClass.name} vs ${rivalClass.name}.',
        ),
      ],
    );

    next = _startTurn(next, first);
    return next;
  }

  DuelPlayer _freshPlayer(String uid, DuelClass duelClass, Random rng) {
    final deck = List<String>.of(duelStarterDeck(classId: duelClass.id))
      ..shuffle(rng);
    return DuelPlayer(
      uid: uid,
      classId: duelClass.id,
      hp: duelClass.maxHp,
      maxHp: duelClass.maxHp,
      block: 0,
      energy: 0,
      maxEnergy: duelClass.maxEnergy,
      vulnerable: 0,
      poison: 0,
      focus: 0,
      hand: const [],
      drawPile: deck,
      discardPile: const [],
    );
  }

  DuelState _startTurn(DuelState state, String uid) {
    final player = state.players[uid];
    if (player == null) throw const DuelException('Player not found.');

    final players = Map<String, DuelPlayer>.of(state.players);
    var current = player;
    var next = state;

    if (current.poison > 0) {
      final poisonDamage = current.poison;
      current = current.copyWith(
        hp: max(0, current.hp - poisonDamage),
        poison: max(0, current.poison - 1),
      );
      players[uid] = current;
      next = next.copyWith(
        players: players,
        log: _appendLog(
          next.log,
          DuelLogEntry(uid: uid, text: 'takes $poisonDamage poison damage.'),
        ),
      );

      if (current.hp <= 0) {
        final winner = next.otherUid(uid);
        return next.copyWith(
          status: 'finished',
          winner: winner,
          log: _appendLog(
            next.log,
            DuelLogEntry(uid: winner, text: 'wins the duel!'),
          ),
        );
      }
    }

    players[uid] = current.copyWith(block: 0, energy: current.maxEnergy);
    next = next.copyWith(
      players: players,
      turn: uid,
      log: _appendLog(
        next.log,
        DuelLogEntry(uid: uid, text: 'starts their turn.'),
      ),
    );
    next = _drawCards(next, uid, handSize);
    return next;
  }

  DuelState _drawCards(DuelState state, String uid, int count) {
    final player = state.players[uid];
    if (player == null) throw const DuelException('Player not found.');

    final hand = List<String>.of(player.hand);
    var drawPile = List<String>.of(player.drawPile);
    var discardPile = List<String>.of(player.discardPile);
    var seed = state.shuffleSeed;

    for (var i = 0; i < count; i++) {
      if (hand.length >= maxHandSize) break;
      if (drawPile.isEmpty) {
        if (discardPile.isEmpty) break;
        drawPile = List<String>.of(discardPile)..shuffle(Random(seed));
        seed += 1;
        discardPile = <String>[];
      }
      hand.add(drawPile.removeLast());
    }

    final updated = player.copyWith(
      hand: hand,
      drawPile: drawPile,
      discardPile: discardPile,
    );
    final players = Map<String, DuelPlayer>.of(state.players);
    players[uid] = updated;
    return state.copyWith(players: players, shuffleSeed: seed);
  }

  int _damageAfterVulnerable(int damage, int vulnerable) {
    if (vulnerable <= 0) return damage;
    return (damage * 3) ~/ 2;
  }

  DuelClass _classFor(String classId) =>
      duelClasses[classId] ?? duelClasses[defaultDuelClassId]!;

  List<DuelLogEntry> _appendLog(List<DuelLogEntry> log, DuelLogEntry entry) {
    final next = List<DuelLogEntry>.of(log)..add(entry);
    if (next.length > maxLogEntries) {
      next.removeRange(0, next.length - maxLogEntries);
    }
    return next;
  }

  void _requireActive(DuelState state) {
    if (!state.isActive) {
      throw const DuelException('This duel is not active.');
    }
  }
}
