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

  test('restart keeps the pair and lets the requester start', () {
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
    expect(next.isActive, isTrue);
  });
}
