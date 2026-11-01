enum KnuckleStatus { active, finished }

class KnuckleException implements Exception {
  KnuckleException(this.message);

  final String message;

  @override
  String toString() => message;
}

class KnucklePlayer {
  KnucklePlayer({required this.uid, required List<List<int>> columns})
    : columns = List<List<int>>.generate(
        KnuckleState.columnCount,
        (index) => List<int>.of(
          index < columns.length ? columns[index] : const <int>[],
        ),
      );

  final String uid;
  final List<List<int>> columns;

  int get score => KnuckleState.boardScore(columns);

  Map<String, dynamic> toMap() => {'uid': uid, 'columns': columns};

  factory KnucklePlayer.fromMap(Map<String, dynamic> map) {
    final rawColumns = map['columns'] as List? ?? const <dynamic>[];
    return KnucklePlayer(
      uid: map['uid'] as String? ?? '',
      columns: [
        for (final column in rawColumns)
          [
            for (final die in (column as List? ?? const <dynamic>[]))
              (die as num).toInt(),
          ],
      ],
    );
  }
}

class KnuckleState {
  KnuckleState({
    required this.gameId,
    required List<String> participants,
    required this.createdBy,
    required this.status,
    required this.turn,
    required this.pendingRoll,
    required List<KnucklePlayer> players,
    required this.winner,
  }) : participants = List<String>.unmodifiable(participants),
       players = List<KnucklePlayer>.unmodifiable(players);

  static const int columnCount = 3;
  static const int maxPerColumn = 3;

  final String gameId;
  final List<String> participants;
  final String createdBy;
  final KnuckleStatus status;
  final String turn;
  final int pendingRoll;
  final List<KnucklePlayer> players;
  final String winner;

  bool get isActive => status == KnuckleStatus.active;
  bool get isFinished => status == KnuckleStatus.finished;

  String otherUid(String uid) {
    if (!participants.contains(uid)) {
      throw KnuckleException('You are not in this game.');
    }
    for (final participant in participants) {
      if (participant != uid) return participant;
    }
    throw KnuckleException('This game needs two players.');
  }

  KnucklePlayer playerFor(String uid) {
    for (final player in players) {
      if (player.uid == uid) return player;
    }
    throw KnuckleException('Player is not in this game.');
  }

  List<List<int>> columnsFor(String uid) => playerFor(uid).columns;

  int scoreFor(String uid) => playerFor(uid).score;

  KnuckleState copyWith({
    KnuckleStatus? status,
    String? turn,
    int? pendingRoll,
    List<KnucklePlayer>? players,
    String? winner,
  }) {
    return KnuckleState(
      gameId: gameId,
      participants: participants,
      createdBy: createdBy,
      status: status ?? this.status,
      turn: turn ?? this.turn,
      pendingRoll: pendingRoll ?? this.pendingRoll,
      players: players ?? this.players,
      winner: winner ?? this.winner,
    );
  }

  Map<String, dynamic> toMap() => {
    'participants': participants,
    'createdBy': createdBy,
    'status': status.name,
    'turn': turn,
    'pendingRoll': pendingRoll,
    'players': [for (final player in players) player.toMap()],
    'winner': winner,
  };

  factory KnuckleState.fromMap(String gameId, Map<String, dynamic> map) {
    final rawParticipants = map['participants'] as List? ?? const <dynamic>[];
    final rawPlayers = map['players'] as List? ?? const <dynamic>[];
    return KnuckleState(
      gameId: gameId,
      participants: [
        for (final participant in rawParticipants) participant.toString(),
      ],
      createdBy: map['createdBy'] as String? ?? '',
      status: map['status'] == KnuckleStatus.finished.name
          ? KnuckleStatus.finished
          : KnuckleStatus.active,
      turn: map['turn'] as String? ?? '',
      pendingRoll: (map['pendingRoll'] as num?)?.toInt() ?? 0,
      players: [
        for (final player in rawPlayers)
          KnucklePlayer.fromMap(Map<String, dynamic>.from(player as Map)),
      ],
      winner: map['winner'] as String? ?? '',
    );
  }

  static int columnScore(List<int> column) {
    final counts = <int, int>{};
    for (final value in column) {
      counts[value] = (counts[value] ?? 0) + 1;
    }
    var total = 0;
    counts.forEach((value, count) {
      total += value * count * count;
    });
    return total;
  }

  static int boardScore(List<List<int>> columns) =>
      columns.fold(0, (total, column) => total + columnScore(column));
}

class KnuckleEngine {
  const KnuckleEngine();

  KnuckleState create({
    required String gameId,
    required String createdBy,
    required String opponentUid,
  }) {
    if (createdBy.isEmpty || opponentUid.isEmpty) {
      throw KnuckleException('Both players are required.');
    }
    if (createdBy == opponentUid) {
      throw KnuckleException('You cannot play against yourself.');
    }
    return KnuckleState(
      gameId: gameId,
      participants: [createdBy, opponentUid],
      createdBy: createdBy,
      status: KnuckleStatus.active,
      turn: createdBy,
      pendingRoll: 0,
      players: [
        KnucklePlayer(uid: createdBy, columns: _emptyColumns()),
        KnucklePlayer(uid: opponentUid, columns: _emptyColumns()),
      ],
      winner: '',
    );
  }

  KnuckleState roll(
    KnuckleState state, {
    required String uid,
    required int value,
  }) {
    _requireParticipant(state, uid);
    if (state.isFinished) {
      throw KnuckleException('The game is already over.');
    }
    if (state.turn != uid) {
      throw KnuckleException('It is not your turn.');
    }
    if (state.pendingRoll != 0) {
      throw KnuckleException('Place the rolled die first.');
    }
    if (value < 1 || value > 6) {
      throw KnuckleException('Invalid die value.');
    }
    return state.copyWith(pendingRoll: value);
  }

  KnuckleState place(
    KnuckleState state, {
    required String uid,
    required int column,
  }) {
    _requireParticipant(state, uid);
    if (state.isFinished) {
      throw KnuckleException('The game is already over.');
    }
    if (state.turn != uid) {
      throw KnuckleException('It is not your turn.');
    }
    if (state.pendingRoll == 0) {
      throw KnuckleException('Roll a die before placing.');
    }
    if (column < 0 || column >= KnuckleState.columnCount) {
      throw KnuckleException('Choose one of the three columns.');
    }

    final me = state.playerFor(uid);
    final them = state.playerFor(state.otherUid(uid));
    if (me.columns[column].length >= KnuckleState.maxPerColumn) {
      throw KnuckleException('That column is full.');
    }

    final value = state.pendingRoll;
    final myColumns = [for (final dice in me.columns) List<int>.of(dice)];
    final theirColumns = [for (final dice in them.columns) List<int>.of(dice)];
    myColumns[column].add(value);
    theirColumns[column].removeWhere((die) => die == value);

    final updatedPlayers = [
      for (final player in state.players)
        KnucklePlayer(
          uid: player.uid,
          columns: player.uid == uid
              ? myColumns
              : player.uid == them.uid
              ? theirColumns
              : player.columns,
        ),
    ];

    final finished = _isFull(myColumns) || _isFull(theirColumns);
    var winner = '';
    if (finished) {
      final myScore = KnuckleState.boardScore(myColumns);
      final theirScore = KnuckleState.boardScore(theirColumns);
      winner = myScore > theirScore
          ? uid
          : theirScore > myScore
          ? them.uid
          : 'draw';
    }

    return state.copyWith(
      status: finished ? KnuckleStatus.finished : KnuckleStatus.active,
      turn: state.otherUid(uid),
      pendingRoll: 0,
      players: updatedPlayers,
      winner: winner,
    );
  }

  KnuckleState rematch(KnuckleState state, {required String uid}) {
    _requireParticipant(state, uid);
    if (!state.isFinished) {
      throw KnuckleException('Finish this game first.');
    }
    return KnuckleState(
      gameId: state.gameId,
      participants: state.participants,
      createdBy: state.createdBy,
      status: KnuckleStatus.active,
      turn: state.turn,
      pendingRoll: 0,
      players: [
        for (final participant in state.participants)
          KnucklePlayer(uid: participant, columns: _emptyColumns()),
      ],
      winner: '',
    );
  }

  static void _requireParticipant(KnuckleState state, String uid) {
    if (!state.participants.contains(uid)) {
      throw KnuckleException('You are not in this game.');
    }
  }

  static List<List<int>> _emptyColumns() =>
      List.generate(KnuckleState.columnCount, (_) => <int>[]);

  static bool _isFull(List<List<int>> columns) =>
      columns.every((column) => column.length >= KnuckleState.maxPerColumn);
}
