import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/duel.dart';
import 'chat_service.dart';
import 'duel_engine.dart';

/// Firestore side of the duel feature.
///
/// A duel has its own document, because chat messages are immutable. The chat
/// message only points at the game id; both players watch the game document
/// and mutate it through transactions.
class DuelService {
  DuelService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final DuelEngine _engine = const DuelEngine();

  DocumentReference<Map<String, dynamic>> _duelRef(
    ChatRoom room,
    String gameId,
  ) => _db
      .collection(room.collection)
      .doc(room.id)
      .collection('games')
      .doc(gameId);

  CollectionReference<Map<String, dynamic>> _messagesFor(ChatRoom room) =>
      _db.collection(room.collection).doc(room.id).collection('messages');

  Stream<DuelState?> watchDuel(ChatRoom room, String gameId) {
    return _duelRef(room, gameId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return null;
      return DuelState.fromMap(snapshot.id, data);
    });
  }

  Future<String> createDuel({
    required ChatRoom room,
    required String uid,
    required String opponentUid,
    String createdByClass = defaultDuelClassId,
    String opponentClass = defaultDuelClassId,
    int? seed,
  }) async {
    final gameRef = _db
        .collection(room.collection)
        .doc(room.id)
        .collection('games')
        .doc();
    final messageRef = _messagesFor(room).doc();
    final state = _engine.create(
      gameId: gameRef.id,
      createdBy: uid,
      opponentUid: opponentUid,
      createdByClass: createdByClass,
      opponentClass: opponentClass,
      firstTurnUid: uid,
      seed: seed,
      lobby: true,
    );

    await _db.runTransaction((txn) async {
      txn.set(gameRef, {
        ...state.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      txn.set(messageRef, {
        'senderId': uid,
        'type': 'game',
        'gameId': gameRef.id,
        'sentAt': FieldValue.serverTimestamp(),
      });
    });

    return gameRef.id;
  }

  Future<void> chooseClass({
    required ChatRoom room,
    required String gameId,
    required String uid,
    required String classId,
  }) {
    return _mutate(
      room,
      gameId,
      (state) => _engine.chooseClass(state, uid: uid, classId: classId),
    );
  }

  Future<void> setReady({
    required ChatRoom room,
    required String gameId,
    required String uid,
    required bool ready,
  }) {
    return _mutate(
      room,
      gameId,
      (state) => _engine.setReady(state, uid: uid, ready: ready),
    );
  }

  Future<void> playCard({
    required ChatRoom room,
    required String gameId,
    required String uid,
    required int handIndex,
  }) {
    return _mutate(
      room,
      gameId,
      (state) => _engine.playCard(state, uid: uid, handIndex: handIndex),
    );
  }

  Future<void> takeRewardDraft({
    required ChatRoom room,
    required String gameId,
    required String uid,
    required String cardId,
  }) {
    return _mutate(
      room,
      gameId,
      (state) => _engine.takeRewardDraft(state, uid: uid, cardId: cardId),
    );
  }

  Future<void> endTurn({
    required ChatRoom room,
    required String gameId,
    required String uid,
  }) {
    return _mutate(room, gameId, (state) => _engine.endTurn(state, uid: uid));
  }

  Future<void> restartDuel({
    required ChatRoom room,
    required String gameId,
    required String uid,
  }) {
    return _mutate(room, gameId, (state) => _engine.restart(state, uid: uid));
  }

  Future<void> _mutate(
    ChatRoom room,
    String gameId,
    DuelState Function(DuelState state) update,
  ) async {
    final ref = _duelRef(room, gameId);
    await _db.runTransaction((txn) async {
      final snapshot = await txn.get(ref);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw const DuelException('Duel not found.');
      }
      final state = DuelState.fromMap(snapshot.id, data);
      final next = update(state);
      txn.set(ref, {
        ...next.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }
}
