import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'chat_service.dart';
import 'knuckle_engine.dart';

class KnuckleService {
  KnuckleService({FirebaseFirestore? db, Random? random})
    : _db = db ?? FirebaseFirestore.instance,
      _random = random ?? Random.secure();

  final FirebaseFirestore _db;
  final Random _random;
  final KnuckleEngine _engine = const KnuckleEngine();

  CollectionReference<Map<String, dynamic>> _gamesFor(ChatRoom room) =>
      _db.collection(room.collection).doc(room.id).collection('games');

  CollectionReference<Map<String, dynamic>> _messagesFor(ChatRoom room) =>
      _db.collection(room.collection).doc(room.id).collection('messages');

  DocumentReference<Map<String, dynamic>> _gameRef(
    ChatRoom room,
    String gameId,
  ) => _gamesFor(room).doc(gameId);

  Stream<KnuckleState?> watchKnuckle(ChatRoom room, String gameId) =>
      _gameRef(room, gameId).snapshots().map((snapshot) {
        final data = snapshot.data();
        if (data == null) {
          throw KnuckleException('This game no longer exists.');
        }
        return KnuckleState.fromMap(snapshot.id, data);
      });

  Future<String> createGame({
    required ChatRoom room,
    required String uid,
    required String opponentUid,
  }) async {
    final gameRef = _gamesFor(room).doc();
    final messageRef = _messagesFor(room).doc();
    final state = _engine.create(
      gameId: gameRef.id,
      createdBy: uid,
      opponentUid: opponentUid,
    );

    final batch = _db.batch();
    batch.set(gameRef, {
      ...state.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(messageRef, {
      'senderId': uid,
      'type': 'game',
      'gameId': gameRef.id,
      'sentAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    return gameRef.id;
  }

  Future<KnuckleState> roll({
    required ChatRoom room,
    required String gameId,
    required String uid,
  }) {
    return _mutate(room, gameId, (state) {
      final value = 1 + _random.nextInt(6);
      return _engine.roll(state, uid: uid, value: value);
    });
  }

  Future<KnuckleState> place({
    required ChatRoom room,
    required String gameId,
    required String uid,
    required int column,
  }) {
    return _mutate(
      room,
      gameId,
      (state) => _engine.place(state, uid: uid, column: column),
    );
  }

  Future<KnuckleState> rematch({
    required ChatRoom room,
    required String gameId,
    required String uid,
  }) {
    return _mutate(room, gameId, (state) => _engine.rematch(state, uid: uid));
  }

  Future<KnuckleState> _mutate(
    ChatRoom room,
    String gameId,
    KnuckleState Function(KnuckleState state) update,
  ) {
    final ref = _gameRef(room, gameId);
    return _db.runTransaction<KnuckleState>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null) {
        throw KnuckleException('Game not found.');
      }
      final current = KnuckleState.fromMap(snapshot.id, data);
      final next = update(current);
      transaction.set(ref, {
        ...next.toMap(),
        'createdAt': data['createdAt'],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return next;
    });
  }
}
