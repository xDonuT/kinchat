import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  const Message({
    required this.id,
    required this.senderId,
    required this.text,
    required this.sentAt,
    this.isPending = false,
    this.replyTo = '',
    this.replyToText = '',
  });

  final String id;
  final String senderId;
  final String text;
  final DateTime sentAt;

  /// Id of the message this one replies to, or '' when it is not a reply.
  final String replyTo;

  /// A saved copy of the quoted text, so a reply renders without a fetch.
  final String replyToText;

  /// True while the server timestamp has not resolved yet, which happens
  /// briefly for a message that was just sent locally.
  final bool isPending;

  factory Message.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final stamp = data?['sentAt'] as Timestamp?;
    return Message(
      id: doc.id,
      senderId: data?['senderId'] as String? ?? '',
      text: data?['text'] as String? ?? '',
      sentAt: stamp?.toDate() ?? DateTime.now(),
      isPending: stamp == null,
      replyTo: data?['replyTo'] as String? ?? '',
      replyToText: data?['replyToText'] as String? ?? '',
    );
  }
}