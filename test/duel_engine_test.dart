import 'package:flutter_test/flutter_test.dart';
import 'package:kinchat/models/duel.dart';
import 'package:kinchat/services/duel_engine.dart';

void main() {
  const engine = DuelEngine();

  DuelState withHand(
    DuelState state,
    String uid,
    List<String> hand, {
    int energy = 3,
    List<String>? drawPile,
    List<String>? discardPile,
  }) {
    final players = Map<String, DuelPlayer>.of(state.players);
    final player = players[uid]!;
    players[uid] = player.copyWith(
      hand: hand,
      energy: energy,
      drawPile: drawPile ?? player.drawPile,
      discardPile: discardPile ?? player.discardPile,
    );
    return state.copyWith(players: players);
  }

  test('starts with the creator on turn and a fresh hand', () {
    final state = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      seed: 1,
    );

    expect(state.isActive, isTrue);
    expect(state.turn, 'a');
    expect(state.turnCount, 1);
    expect(state.round, 1);
    expect(state.player('a')!.hp, DuelEngine.startingHp);
    expect(state.player('a')!.hand.length, DuelEngine.handSize);
    expect(state.player('a')!.energy, DuelEngine.maxEnergy);
    expect(state.player('b')!.hand, isEmpty);
  });

  test('playing Strike spends energy and damages the opponent', () {
    final base = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      seed: 2,
    );
    final state = withHand(base, 'a', ['strike']);

    final next = engine.playCard(state, uid: 'a', handIndex: 0);

    expect(next.player('a')!.energy, 2);
    expect(next.player('b')!.hp, 44);
    expect(next.player('a')!.hand, isEmpty);
    expect(next.player('a')!.discardPile, contains('strike'));
  });

  test('block absorbs damage and resets when its owner starts a turn', () {
    final base = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      seed: 3,
    );

    var state = withHand(base, 'a', ['defend', 'defend']);
    state = engine.playCard(state, uid: 'a', handIndex: 0);
    state = engine.playCard(state, uid: 'a', handIndex: 0);
    expect(state.player('a')!.block, 10);

    final players = Map<String, DuelPlayer>.of(state.players);
    players['b'] = players['b']!.copyWith(hand: ['strike'], energy: 3);
    state = state.copyWith(turn: 'b', players: players);

    state = engine.playCard(state, uid: 'b', handIndex: 0);
    expect(state.player('a')!.hp, DuelEngine.startingHp);
    expect(state.player('a')!.block, 4);

    state = engine.endTurn(state, uid: 'b');
    expect(state.turn, 'a');
    expect(state.player('a')!.block, 0);
  });

  test('Vulnerable increases the next attack by 50 percent', () {
    final base = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      seed: 4,
    );

    var state = withHand(base, 'a', ['bash']);
    state = engine.playCard(state, uid: 'a', handIndex: 0);
    expect(state.player('b')!.hp, 42);
    expect(state.player('b')!.vulnerable, 2);

    state = withHand(state, 'a', ['strike']);
    state = engine.playCard(state, uid: 'a', handIndex: 0);
    expect(state.player('b')!.hp, 33);
  });

  test('draw effects reshuffle the discard pile when needed', () {
    final base = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      seed: 5,
    );
    var state = withHand(
      base,
      'a',
      ['shrug_it_off'],
      drawPile: const [],
      discardPile: const [],
    );

    state = engine.playCard(state, uid: 'a', handIndex: 0);

    expect(state.player('a')!.hand, contains('shrug_it_off'));
    expect(state.player('a')!.discardPile, isEmpty);
  });

  test('ending a turn discards the hand and draws a fresh one', () {
    final base = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      seed: 6,
    );

    final next = engine.endTurn(base, uid: 'a');

    expect(next.turn, 'b');
    expect(next.turnCount, 2);
    expect(next.player('a')!.hand, isEmpty);
    expect(next.player('a')!.discardPile.length, DuelEngine.handSize);
    expect(next.player('b')!.hand.length, DuelEngine.handSize);
    expect(next.player('b')!.energy, DuelEngine.maxEnergy);
  });

  test('reduces the loser to zero and marks the duel finished', () {
    final base = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      seed: 7,
    );
    final players = Map<String, DuelPlayer>.of(base.players);
    players['b'] = players['b']!.copyWith(hp: 4);
    players['a'] = players['a']!.copyWith(hand: ['strike'], energy: 3);
    final state = base.copyWith(players: players);

    final next = engine.playCard(state, uid: 'a', handIndex: 0);

    expect(next.isFinished, isTrue);
    expect(next.winner, 'a');
    expect(next.player('b')!.hp, 0);
  });

  test('rejects moves from the wrong player and unaffordable cards', () {
    final base = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      seed: 8,
    );

    expect(
      () => engine.playCard(base, uid: 'b', handIndex: 0),
      throwsA(isA<DuelException>()),
    );

    final state = withHand(base, 'a', ['heavy_blow'], energy: 1);
    expect(
      () => engine.playCard(state, uid: 'a', handIndex: 0),
      throwsA(isA<DuelException>()),
    );
  });

  test('restart returns to a lobby and lets the requester start', () {
    final base = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      seed: 9,
    );
    final finished = base.copyWith(status: 'finished', winner: 'a');

    final next = engine.restart(finished, uid: 'b', seed: 10);

    expect(next.participants, ['a', 'b']);
    expect(next.createdBy, 'a');
    expect(next.turn, 'b');
    expect(next.isLobby, isTrue);
    expect(next.player('a')!.ready, isFalse);
    expect(next.player('b')!.ready, isFalse);

    var started = engine.setReady(next, uid: 'a', ready: true);
    expect(started.isLobby, isTrue);
    started = engine.setReady(started, uid: 'b', ready: true);
    expect(started.isActive, isTrue);
    expect(started.turn, 'b');
    expect(started.player('b')!.hand.length, 5);
    expect(started.player('a')!.hand, isEmpty);
  });

  test('lobby waits for both players and uses each chosen class', () {
    var state = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      seed: 18,
      lobby: true,
    );

    expect(state.isLobby, isTrue);
    expect(state.player('a')!.hand, isEmpty);
    expect(state.player('a')!.ready, isFalse);

    state = engine.chooseClass(state, uid: 'a', classId: 'ninja');
    state = engine.chooseClass(state, uid: 'b', classId: 'wizard');
    expect(state.player('a')!.classId, 'ninja');
    expect(state.player('b')!.classId, 'wizard');

    state = engine.setReady(state, uid: 'a', ready: true);
    expect(state.isLobby, isTrue);
    state = engine.setReady(state, uid: 'b', ready: true);

    expect(state.isActive, isTrue);
    expect(state.turn, 'a');
    expect(state.player('a')!.maxHp, 42);
    expect(state.player('b')!.maxHp, 44);
    expect(state.player('a')!.hand.length, 5);
  });

  test('changing class clears ready and active duels reject lobby actions', () {
    var state = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      seed: 19,
      lobby: true,
    );

    state = engine.setReady(state, uid: 'a', ready: true);
    expect(state.player('a')!.ready, isTrue);
    state = engine.chooseClass(state, uid: 'a', classId: 'wizard');
    expect(state.player('a')!.ready, isFalse);
    expect(state.player('a')!.classId, 'wizard');

    final active = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      seed: 20,
    );
    expect(
      () => engine.chooseClass(active, uid: 'a', classId: 'ninja'),
      throwsA(isA<DuelException>()),
    );
    expect(engine.setReady(active, uid: 'a', ready: true).status, 'active');
  });

  test('defaults both players to Knight and the Knight deck', () {
    final state = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      seed: 11,
    );
    final a = state.player('a')!;
    final b = state.player('b')!;

    expect(a.classId, 'knight');
    expect(b.classId, 'knight');
    expect(a.maxHp, 50);
    expect(b.maxHp, 50);
    final cards = [...a.hand, ...a.drawPile];
    expect(
      cards,
      containsAll(['bash', 'iron_wave', 'heavy_blow', 'shrug_it_off']),
    );
    expect(cards.length, 10);
  });

  test('Ninja and Wizard use their own HP and starter cards', () {
    final state = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      createdByClass: 'ninja',
      opponentClass: 'wizard',
      seed: 12,
    );
    final ninja = state.player('a')!;
    final wizard = state.player('b')!;

    expect(ninja.classId, 'ninja');
    expect(ninja.maxHp, 42);
    expect(wizard.classId, 'wizard');
    expect(wizard.maxHp, 44);

    final ninjaCards = [...ninja.hand, ...ninja.drawPile];
    expect(
      ninjaCards,
      containsAll([
        'quick_jab',
        'pommel_strike',
        'poison_stab',
        'deadly_poison',
      ]),
    );
    final wizardCards = [...wizard.hand, ...wizard.drawPile];
    expect(
      wizardCards,
      containsAll(['zap', 'arcane_bolt', 'mana_shield', 'fireball']),
    );
  });

  test('Poison ignores block and ticks at the start of the victim turn', () {
    final base = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      seed: 13,
    );
    final players = Map<String, DuelPlayer>.of(base.players);
    players['b'] = players['b']!.copyWith(hp: 20, block: 10, poison: 3);
    var state = base.copyWith(players: players);

    state = engine.endTurn(state, uid: 'a');
    expect(state.player('b')!.hp, 17);
    expect(state.player('b')!.poison, 2);
    expect(state.player('b')!.block, 0);

    state = engine.endTurn(state, uid: 'b');
    state = engine.endTurn(state, uid: 'a');
    expect(state.player('b')!.hp, 15);
    expect(state.player('b')!.poison, 1);
  });

  test('Poison can finish the duel at the start of a turn', () {
    final base = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      seed: 14,
    );
    final players = Map<String, DuelPlayer>.of(base.players);
    players['b'] = players['b']!.copyWith(hp: 2, poison: 5);

    final state = engine.endTurn(base.copyWith(players: players), uid: 'a');

    expect(state.isFinished, isTrue);
    expect(state.winner, 'a');
    expect(state.player('b')!.hp, 0);
  });

  test('Focus empowers cards that scale with it', () {
    final base = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      createdByClass: 'wizard',
      opponentClass: 'knight',
      seed: 15,
    );
    var state = withHand(base, 'a', ['zap', 'zap', 'arcane_bolt']);

    state = engine.playCard(state, uid: 'a', handIndex: 0);
    expect(state.player('a')!.focus, 1);
    state = engine.playCard(state, uid: 'a', handIndex: 0);
    expect(state.player('a')!.focus, 2);
    state = engine.playCard(state, uid: 'a', handIndex: 0);

    expect(state.player('b')!.hp, 42);
    expect(state.player('a')!.energy, 2);
  });

  test('rematch keeps each player class', () {
    final base = engine.create(
      gameId: 'g',
      createdBy: 'a',
      opponentUid: 'b',
      createdByClass: 'ninja',
      opponentClass: 'wizard',
      seed: 16,
    );
    final finished = base.copyWith(status: 'finished', winner: 'a');

    final next = engine.restart(finished, uid: 'b', seed: 17);

    expect(next.player('a')!.classId, 'ninja');
    expect(next.player('b')!.classId, 'wizard');
    expect(next.player('a')!.maxHp, 42);
    expect(next.player('b')!.maxHp, 44);
    expect(next.turn, 'b');
  });

  test('old duel players default to Knight and no new statuses', () {
    final player = DuelPlayer.fromMap('a', {'hp': 50, 'maxHp': 50});

    expect(player.classId, 'knight');
    expect(player.poison, 0);
    expect(player.focus, 0);
    expect(player.ready, isFalse);
  });
}
