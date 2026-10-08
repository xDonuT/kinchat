import 'package:cloud_firestore/cloud_firestore.dart';

/// One emoji a member placed on a message. Stored as its own small document
/// so the message documents themselves stay immutable.
class Reaction {
  const Reaction({required this.uid, required this.emoji});

  final String uid;
  final String emoji;

  factory Reaction.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Reaction(
      uid: doc.id,
      emoji: data?['emoji'] as String? ?? '',
    );
  }
}