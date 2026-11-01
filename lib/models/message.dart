import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  const Message({
    required this.id,
    required this.senderId,
    required this.text,
    required this.sentAt,
    this.type = 'text',
    this.gameId = '',
    this.imageUrl = '',
    this.imagePath = '',
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.isPending = false,
    this.replyTo = '',
    this.replyToText = '',
  });

  final String id;
  final String senderId;
  final String text;
  final DateTime sentAt;

  /// 'text', 'image', or 'game'. Messages written before photos existed have
  /// no type field and are treated as text.
  final String type;

  /// Id of the Knucklebones game document for a game message, or ''.
  final String gameId;

  /// Download URL and Storage path for a photo message. Empty for text.
  final String imageUrl;
  final String imagePath;

  /// Pixel dimensions, used to reserve the right space before the photo loads
  /// so the list does not jump around while scrolling.
  final int imageWidth;
  final int imageHeight;

  /// Id of the message this one replies to, or '' when it is not a reply.
  final String replyTo;

  /// A saved copy of the quoted text, so a reply renders without a fetch.
  final String replyToText;

  /// True while the server timestamp has not resolved yet, which happens
  /// briefly for a message that was just sent locally.
  final bool isPending;

  bool get isGame => type == 'game' || gameId.isNotEmpty;

  bool get isImage => type == 'image' || imageUrl.isNotEmpty;

  /// Short label used when this message is quoted or shown in a notification.
  String get preview {
    if (isGame) return '[Knucklebones]';
    return isImage ? '[Photo]' : text;
  }

  factory Message.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final stamp = data?['sentAt'] as Timestamp?;
    final imageUrl = data?['imageUrl'] as String? ?? '';
    return Message(
      id: doc.id,
      senderId: data?['senderId'] as String? ?? '',
      text: data?['text'] as String? ?? '',
      sentAt: stamp?.toDate() ?? DateTime.now(),
      type: data?['type'] as String? ?? (imageUrl.isEmpty ? 'text' : 'image'),
      gameId: data?['gameId'] as String? ?? '',
      imageUrl: imageUrl,
      imagePath: data?['imagePath'] as String? ?? '',
      imageWidth: (data?['imageWidth'] as num?)?.toInt() ?? 0,
      imageHeight: (data?['imageHeight'] as num?)?.toInt() ?? 0,
      isPending: stamp == null,
      replyTo: data?['replyTo'] as String? ?? '',
      replyToText: data?['replyToText'] as String? ?? '',
    );
  }
}
