import 'package:cloud_firestore/cloud_firestore.dart';

/// A family member's public profile: enough to show a name in the chats.
class Profile {
  const Profile({
    required this.uid,
    required this.displayName,
    required this.email,
  });

  final String uid;
  final String displayName;
  final String email;

  /// Never trust the stored value blindly - a profile written before the
  /// display-name feature existed could be missing or blank.
  String get safeName {
    final name = displayName.trim();
    if (name.isNotEmpty) return name;
    final fromEmail = email.split('@').first.trim();
    return fromEmail.isEmpty ? 'Family member' : fromEmail;
  }

  factory Profile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Profile(
      uid: doc.id,
      displayName: (data['displayName'] ?? '') as String,
      email: (data['email'] ?? '') as String,
    );
  }
}
