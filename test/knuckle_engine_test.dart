import 'package:flutter_test/flutter_test.dart';
import 'package:kinchat/services/knuckle_engine.dart';

void main() {
  const engine = KnuckleEngine();

  KnuckleState stateWith({
    String turn = 'a',
    int pendingRoll = 0,
    List<List<int>>? a,
    List<List<int>>? b,
    KnuckleStatus status = KnuckleStatus.active,
    String winner = '',
  }) {
    return KnuckleState(
      gameId: 'game',
      participants: const ['a', 'b'],
      createdBy: 'a',
      status: status,
      turn: turn,
      pendingRoll: pendingRoll,
      players: [
        KnucklePlayer(uid: 'a', columns: a ?? [[], [], []]),
        KnucklePlayer(uid: 'b', columns: b ?? [[], [], []]),
      ],
      winner: winner,
    );
  }

  group('scoring', () {
    test('column scores multiply duplicates', () {
      expect(KnuckleState.columnScore([]), 0);
      expect(KnuckleState.columnScore([4, 1, 4]), 17);
      expect(KnuckleState.columnScore([5, 5, 5]), 45);
      expect(KnuckleState.columnScore([1, 2, 3]), 6);
    });

    test('board score sums the columns', () {
      final columns = [
        [4, 1, 4],
        [5, 5, 5],
        [2],
      ];
      expect(KnuckleState.boardScore(columns), 17 + 45 + 2);
    });
  });

  test('create starts an active game with the creator to move', () {
    final game = engine.create(gameId: 'g1', createdBy: 'a', opponentUid: 'b');

    expect(game.gameId, 'g1');
    expect(game.participants, ['a', 'b']);
    expect(game.createdBy, 'a');
    expect(game.isActive, isTrue);
    expect(game.turn, 'a');
    expect(game.pendingRoll, 0);
    expect(game.winner, '');
    expect(game.playerFor('a').columns.every((c) => c.isEmpty), isTrue);
    expect(game.playerFor('b').columns.every((c) => c.isEmpty), isTrue);
    expect(
      () => engine.create(gameId: 'g', createdBy: 'a', opponentUid: 'a'),
      throwsA(isA<KnuckleException>()),
    );
  });

  test('rolling is limited to the player whose turn it is', () {
    final game = engine.create(gameId: 'g1', createdBy: 'a', opponentUid: 'b');

    final rolled = engine.roll(game, uid: 'a', value: 6);
    expect(rolled.pendingRoll, 6);

    expect(
      () => engine.roll(game, uid: 'b', value: 3),
      throwsA(isA<KnuckleException>()),
    );
    expect(
      () => engine.roll(rolled, uid: 'a', value: 3),
      throwsA(isA<KnuckleException>()),
    );
    expect(
      () => engine.roll(game, uid: 'a', value: 7),
      throwsA(isA<KnuckleException>()),
    );
  });

  test('placing fills the column and passes the turn', () {
    final game = engine.create(gameId: 'g1', createdBy: 'a', opponentUid: 'b');
    final rolled = engine.roll(game, uid: 'a', value: 6);

    final placed = engine.place(rolled, uid: 'a', column: 1);

    expect(placed.playerFor('a').columns[1], [6]);
    expect(placed.pendingRoll, 0);
    expect(placed.turn, 'b');
    expect(
      () => engine.place(placed, uid: 'a', column: 0),
      throwsA(isA<KnuckleException>()),
    );
    expect(
      () => engine.place(game, uid: 'a', column: 0),
      throwsA(isA<KnuckleException>()),
    );
  });

  test('placing destroys matching dice in the same rival column only', () {
    final game = stateWith(
      pendingRoll: 4,
      b: [
        [4, 1, 4],
        [4, 4, 2],
        [3],
      ],
    );

    final placed = engine.place(game, uid: 'a', column: 0);

    expect(placed.playerFor('a').columns[0], [4]);
    expect(placed.playerFor('b').columns[0], [1]);
    expect(placed.playerFor('b').columns[1], [4, 4, 2]);
    expect(placed.playerFor('b').columns[2], [3]);
  });

  test('a full column cannot take another die', () {
    final game = stateWith(
      pendingRoll: 2,
      a: [
        [1, 2, 3],
        [],
        [],
      ],
    );

    expect(
      () => engine.place(game, uid: 'a', column: 0),
      throwsA(isA<KnuckleException>()),
    );

    final placed = engine.place(game, uid: 'a', column: 1);
    expect(placed.playerFor('a').columns[1], [2]);
  });

  test('filling a board finishes the game and scores decide the winner', () {
    final game = stateWith(
      pendingRoll: 6,
      a: [
        [1, 2, 3],
        [4, 5],
        [6, 6, 6],
      ],
      b: [
        [1],
        [2],
        [3],
      ],
    );

    final placed = engine.place(game, uid: 'a', column: 1);

    expect(placed.isFinished, isTrue);
    expect(placed.winner, 'a');
    expect(placed.scoreFor('a'), 75);
    expect(placed.scoreFor('b'), 6);
    expect(placed.pendingRoll, 0);
  });

  test('equal final scores are a draw', () {
    final game = stateWith(
      pendingRoll: 2,
      a: [
        [1, 1, 1],
        [1, 1, 1],
        [2, 2],
      ],
      b: [
        [2, 2, 2],
        [1, 1, 1],
        [1, 1, 1],
      ],
    );

    final placed = engine.place(game, uid: 'a', column: 2);

    expect(placed.isFinished, isTrue);
    expect(placed.winner, 'draw');
    expect(placed.scoreFor('a'), 36);
    expect(placed.scoreFor('b'), 36);
  });

  test('rematch resets the boards and alternates the first turn', () {
    final finished = stateWith(
      turn: 'b',
      status: KnuckleStatus.finished,
      winner: 'a',
      a: [
        [1, 1, 1],
        [1, 1, 1],
        [1, 1, 1],
      ],
      b: [
        [2],
        [2],
        [2],
      ],
    );

    final next = engine.rematch(finished, uid: 'b');

    expect(next.isActive, isTrue);
    expect(next.turn, 'b');
    expect(next.pendingRoll, 0);
    expect(next.winner, '');
    expect(next.playerFor('a').columns.every((c) => c.isEmpty), isTrue);
    expect(next.playerFor('b').columns.every((c) => c.isEmpty), isTrue);

    expect(
      () => engine.rematch(stateWith(), uid: 'a'),
      throwsA(isA<KnuckleException>()),
    );
    expect(
      () => engine.rematch(finished, uid: 'c'),
      throwsA(isA<KnuckleException>()),
    );
  });

  test('serializes and restores the full game state', () {
    final game = stateWith(
      pendingRoll: 4,
      a: [
        [1, 2, 3],
        [4, 5],
        [6, 6, 6],
      ],
      b: [
        [1],
        [2],
        [3],
      ],
    );

    final restored = KnuckleState.fromMap(game.gameId, game.toMap());

    expect(restored.participants, game.participants);
    expect(restored.createdBy, game.createdBy);
    expect(restored.status, game.status);
    expect(restored.turn, game.turn);
    expect(restored.pendingRoll, game.pendingRoll);
    expect(restored.winner, game.winner);
    expect(restored.playerFor('a').columns, game.playerFor('a').columns);
    expect(restored.playerFor('b').columns, game.playerFor('b').columns);
    expect(restored.toMap(), game.toMap());
  });

  test('rejects retired duel documents', () {
    expect(
      () => KnuckleState.fromMap('game', {
        'participants': ['a', 'b'],
        'createdBy': 'a',
        'status': 'lobby',
        'turn': 'a',
        'players': {'a': <String, dynamic>{}, 'b': <String, dynamic>{}},
      }),
      throwsA(isA<KnuckleException>()),
    );
  });

  test('rejects players outside the game', () {
    final game = stateWith();

    expect(
      () => engine.roll(game, uid: 'c', value: 1),
      throwsA(isA<KnuckleException>()),
    );
    expect(
      () => engine.place(game, uid: 'c', column: 0),
      throwsA(isA<KnuckleException>()),
    );
    expect(() => game.otherUid('c'), throwsA(isA<KnuckleException>()));
  });
}
