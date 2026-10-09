import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/message.dart';
import '../models/reaction.dart';

/// Where a conversation lives in Firestore.
///
/// The family group is a single shared room under `chats/`; private threads
/// live under `conversations/`, one document per pair of people.
class ChatRoom {
  const ChatRoom.group()
      : collection = 'chats',
        id = 'main',
        isPrivate = false;

  const ChatRoom.private(String conversationId)
      : collection = 'conversations',
        id = conversationId,
        isPrivate = true;

  final String collection;
  final String id;
  final bool isPrivate;
}

/// Everything the app does with messages.
class ChatService {
  ChatService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _messagesFor(ChatRoom room) =>
      _db.collection(room.collection).doc(room.id).collection('messages');

  /// Oldest first, live (newest settles at the bottom of the chat).
  /// Errors surface through the stream so the UI can show "check your
  /// security rules" instead of an empty list.
  Stream<List<Message>> watchMessages(ChatRoom room) {
    return _messagesFor(room)
        .orderBy('sentAt')
        .snapshots()
        .map((snap) => snap.docs.map(Message.fromDoc).toList());
  }

  /// Writes a message the security rules will accept: your own uid, a
  /// non-empty trimmed body capped at 2000 characters, and only the fields
  /// the rules expect. When [replyTo] is set, the message quotes it.
  Future<void> send({
    required ChatRoom room,
    required String senderId,
    required String text,
    String replyTo = '',
    String replyToText = '',
  }) async {
    final body = text.trim();
    if (body.isEmpty) return;
    if (body.length > 2000) {
      throw ArgumentError('Message is too long (max 2000 characters).');
    }

    await _messagesFor(room).add({
      'senderId': senderId,
      'text': body,
      'sentAt': FieldValue.serverTimestamp(),
      'replyTo': replyTo,
      'replyToText': replyToText.trim(),
    });
  }

  /// Permanently deletes every message (and its reactions) in a chat, for
  /// everyone. Writes are batched to stay well under Firestore's limits.
  Future<void> clearChat(ChatRoom room) async {
    final messages = await _messagesFor(room).get();
    var batch = _db.batch();
    var ops = 0;
    Future<void> flush() async {
      if (ops == 0) return;
      await batch.commit();
      batch = _db.batch();
      ops = 0;
    }
    for (final message in messages.docs) {
      final likes = await message.reference.collection('reactions').get();
      for (final like in likes.docs) {
        batch.delete(like.reference);
        ops++;
        if (ops >= 400) await flush();
      }
      batch.delete(message.reference);
      ops++;
      if (ops >= 400) await flush();
    }
    await flush();
  }

  CollectionReference<Map<String, dynamic>> _reactionsFor(
          ChatRoom room, String messageId) =>
      _db
          .collection(room.collection)
          .doc(room.id)
          .collection('messages')
          .doc(messageId)
          .collection('reactions');

  /// Live reactions on one message (each member reacts at most once).
  Stream<List<Reaction>> watchReactions(ChatRoom room, String messageId) {
    return _reactionsFor(room, messageId)
        .snapshots()
        .map((snap) => snap.docs.map(Reaction.fromDoc).toList());
  }

  /// Reads back what you reacted with, if anything.
  Future<String?> currentReaction(
      ChatRoom room, String messageId, String userId) async {
    final doc = await _reactionsFor(room, messageId).doc(userId).get();
    return doc.exists ? (doc.data()?['emoji'] as String?) : null;
  }

  Future<void> react({
    required ChatRoom room,
    required String messageId,
    required String userId,
    required String emoji,
  }) async {
    if (emoji.trim().isEmpty || emoji.length > 16) {
      throw ArgumentError('Invalid emoji.');
    }
    await _reactionsFor(room, messageId).doc(userId).set({'emoji': emoji});
  }

  Future<void> unreact({
    required ChatRoom room,
    required String messageId,
    required String userId,
  }) {
    return _reactionsFor(room, messageId).doc(userId).delete();
  }
}
