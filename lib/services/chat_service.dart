import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

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
  final FirebaseStorage _storage = FirebaseStorage.instance;

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

  /// Uploads a photo to Storage and writes the message that points at it.
  /// The image is expected to be pre-shrunk on-device (maxWidth ~1600,
  /// quality ~75 %) so a family photo stays comfortably inside the free
  /// storage tier.
  Future<void> sendPhoto({
    required ChatRoom room,
    required String senderId,
    required String path,
    String replyTo = '',
    String replyToText = '',
  }) async {
    final ref = _messagesFor(room).doc();
    final ext = path.split('.').last.toLowerCase();
    final safeExt = const ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext)
        ? ext
        : 'jpg';
    final contentType = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      'gif': 'image/gif',
    }[safeExt]!;
    final storageRef =
        _storage.ref('chats/${room.collection}/${room.id}/${ref.id}.$safeExt');
    final bytes = await File(path).readAsBytes();
    await storageRef.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    final imageUrl = await storageRef.getDownloadURL();
    await ref.set({
      'senderId': senderId,
      'type': 'image',
      'text': '',
      'sentAt': FieldValue.serverTimestamp(),
      'replyTo': replyTo,
      'replyToText': replyToText.trim(),
      'imageUrl': imageUrl,
    });
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
