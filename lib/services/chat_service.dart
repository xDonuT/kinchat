import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/message.dart';
import '../models/reaction.dart';

/// Where a 1:1 conversation lives in Firestore.
///
/// Each private thread lives under `conversations/`, one document per pair of
/// people, keyed by their sorted UIDs.
class ChatRoom {
  const ChatRoom.private(String conversationId)
    : collection = 'conversations',
      id = conversationId;

  final String collection;
  final String id;
}

/// Everything the app does with messages.
class ChatService {
  ChatService({FirebaseFirestore? db, FirebaseStorage? storage})
    : _db = db ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

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

  /// Uploads a compressed photo, then writes the message that references it.
  ///
  /// The upload reports progress through [onProgress] (0..1). If the Firestore
  /// write fails, the uploaded object is removed so it does not become an
  /// orphan. The photo is stored beside the message id, which is generated
  /// before the upload starts.
  Future<void> sendImage({
    required ChatRoom room,
    required String senderId,
    required Uint8List bytes,
    required int width,
    required int height,
    String replyTo = '',
    String replyToText = '',
    void Function(double progress)? onProgress,
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError('Image is empty.');
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Image has invalid dimensions.');
    }

    final doc = _messagesFor(room).doc();
    final path = 'conversations/${room.id}/messages/${doc.id}.jpg';
    final ref = _storage.ref(path);

    final task = ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final subscription = task.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes > 0) {
        onProgress?.call(
          (snapshot.bytesTransferred / snapshot.totalBytes).clamp(0.0, 1.0),
        );
      }
    }, onError: (_) {});

    try {
      await task;
      final imageUrl = await ref.getDownloadURL();
      await doc.set({
        'senderId': senderId,
        'type': 'image',
        'imageUrl': imageUrl,
        'imagePath': path,
        'imageWidth': width,
        'imageHeight': height,
        'sentAt': FieldValue.serverTimestamp(),
        'replyTo': replyTo,
        'replyToText': replyToText.trim(),
      });
      onProgress?.call(1);
    } catch (_) {
      try {
        await ref.delete();
      } catch (_) {
        // The upload may never have completed; there is nothing to clean up.
      }
      rethrow;
    } finally {
      await subscription.cancel();
    }
  }

  /// Permanently deletes every message (and its reactions) in a chat, for
  /// everyone. Writes are batched to stay well under Firestore's limits.
  /// Uploaded photos are removed from Storage afterwards.
  Future<void> clearChat(ChatRoom room) async {
    final messages = await _messagesFor(room).get();
    final imagePaths = <String>[];
    var batch = _db.batch();
    var ops = 0;
    Future<void> flush() async {
      if (ops == 0) return;
      await batch.commit();
      batch = _db.batch();
      ops = 0;
    }

    for (final message in messages.docs) {
      final imagePath = message.data()['imagePath'];
      if (imagePath is String && imagePath.isNotEmpty) {
        imagePaths.add(imagePath);
      }
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

    // Documents are gone at this point, so a failed Storage delete can only
    // leave an unreferenced file behind - never a broken message.
    for (final path in imagePaths) {
      try {
        await _storage.ref(path).delete();
      } catch (_) {
        // Already missing; clearing the chat still succeeded.
      }
    }
  }

  CollectionReference<Map<String, dynamic>> _reactionsFor(
    ChatRoom room,
    String messageId,
  ) => _db
      .collection(room.collection)
      .doc(room.id)
      .collection('messages')
      .doc(messageId)
      .collection('reactions');

  /// Live reactions on one message (each member reacts at most once).
  Stream<List<Reaction>> watchReactions(ChatRoom room, String messageId) {
    return _reactionsFor(
      room,
      messageId,
    ).snapshots().map((snap) => snap.docs.map(Reaction.fromDoc).toList());
  }

  /// Reads back what you reacted with, if anything.
  Future<String?> currentReaction(
    ChatRoom room,
    String messageId,
    String userId,
  ) async {
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
