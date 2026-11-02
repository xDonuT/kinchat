import 'knuckle_ai_profile.dart';
import 'knuckle_engine.dart';

class KnuckleAi {
  const KnuckleAi();

  static const KnuckleEngine _engine = KnuckleEngine();
  static const int _winScore = 1000000000;
  static const int _lossScore = -1000000000;
  static const int _drawScore = -5000000;

  int chooseColumn({
    required KnuckleState state,
    required String aiUid,
    KnuckleAiDifficulty difficulty = KnuckleAiDifficulty.normal,
    KnuckleAiProfile profile = const KnuckleAiProfile(),
  }) {
    if (state.pendingRoll == 0) {
      throw KnuckleException('The AI needs a rolled die first.');
    }
    final opponentUid = state.otherUid(aiUid);
    var bestColumn = -1;
    var bestScore = _lossScore;

    for (var column = 0; column < KnuckleState.columnCount; column++) {
      if (state.columnsFor(aiUid)[column].length >= KnuckleState.maxPerColumn) {
        continue;
      }
      final placed = _engine.place(state, uid: aiUid, column: column);
      var score = difficulty == KnuckleAiDifficulty.easy
          ? _evaluate(placed, aiUid, opponentUid)
          : _scoreAfterPlacement(placed, aiUid, opponentUid);
      if (difficulty == KnuckleAiDifficulty.hard) {
        score += _adaptiveBonus(
          before: state,
          after: placed,
          opponentUid: opponentUid,
          column: column,
          profile: profile,
        );
      }
      if (bestColumn == -1 || score > bestScore) {
        bestColumn = column;
        bestScore = score;
      }
    }

    if (bestColumn == -1) {
      throw KnuckleException('The AI has no open column.');
    }
    return bestColumn;
  }

  int _adaptiveBonus({
    required KnuckleState before,
    required KnuckleState after,
    required String opponentUid,
    required int column,
    required KnuckleAiProfile profile,
  }) {
    final bias = profile.columnBias(column);
    if (bias <= 0) return 0;

    final beforeCount = before.columnsFor(opponentUid)[column].length;
    final afterCount = after.columnsFor(opponentUid)[column].length;
    final removed = beforeCount - afterCount;
    final laneBonus = (bias * 30000).round();
    final denyBonus = (removed * (0.5 + bias) * 3000).round();
    return laneBonus + denyBonus;
  }

  int _scoreAfterPlacement(
    KnuckleState placed,
    String aiUid,
    String opponentUid,
  ) {
    if (placed.isFinished) return _evaluate(placed, aiUid, opponentUid);

    var total = 0;
    for (var die = 1; die <= 6; die++) {
      KnuckleState rolled;
      try {
        rolled = _engine.roll(placed, uid: opponentUid, value: die);
      } catch (_) {
        total += _evaluate(placed, aiUid, opponentUid);
        continue;
      }

      int? bestReply;
      for (var column = 0; column < KnuckleState.columnCount; column++) {
        if (rolled.columnsFor(opponentUid)[column].length >=
            KnuckleState.maxPerColumn) {
          continue;
        }
        try {
          final replied = _engine.place(
            rolled,
            uid: opponentUid,
            column: column,
          );
          final score = _evaluate(replied, aiUid, opponentUid);
          if (bestReply == null || score > bestReply) bestReply = score;
        } catch (_) {
          continue;
        }
      }
      total += bestReply ?? _evaluate(rolled, aiUid, opponentUid);
    }
    return total ~/ 6;
  }

  int _evaluate(KnuckleState state, String aiUid, String opponentUid) {
    final difference = state.scoreFor(aiUid) - state.scoreFor(opponentUid);
    if (state.isFinished) {
      if (state.winner == aiUid) return _winScore + difference;
      if (state.winner == 'draw') return _drawScore + difference;
      return _lossScore + difference;
    }

    var value = difference * 1000;
    for (final column in state.columnsFor(aiUid)) {
      final counts = <int, int>{};
      for (final die in column) {
        counts[die] = (counts[die] ?? 0) + 1;
      }
      counts.forEach((die, count) {
        if (count > 1) value += die * (count - 1) * 250;
      });
      if (column.length == 2 && column[0] != column[1]) value -= 120;
    }
    return value;
  }
}
