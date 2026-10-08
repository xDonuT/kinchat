import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/message.dart';

class ChatService {
  ChatService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// There is only ever one conversation in this app, so a fixed id keeps the
  /// data model simple and lets the security rules hardcode it.
  static const String chatId = 'main';

  static const int pageSize = 200;

  CollectionReference<Map<String, dynamic>> get _messages =>
      _db.collection('chats').doc(chatId).collection('messages');

  /// Live stream of the conversation, oldest first. Only the most recent
  /// [pageSize] messages are fetched to stay inside the Firestore free tier.
  Stream<List<Message>> watchMessages() {
    return _messages
        .orderBy('sentAt', descending: false)
        .limitToLast(pageSize)
        .snapshots()
        .map((snap) => snap.docs.map(Message.fromDoc).toList());
  }

  Future<void> send({required String senderId, required String text}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Future.value();
    return _messages.add({
      'senderId': senderId,
      'text': trimmed,
      'sentAt': FieldValue.serverTimestamp(),
    });
  }
}