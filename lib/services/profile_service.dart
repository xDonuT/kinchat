import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/profile.dart';

/// Reads and writes the `users/{uid}` profile documents.
///
/// Profiles exist purely so chat bubbles can say *who* wrote something.
/// Only ever writes your own profile - the security rules enforce that.
class ProfileService {
  ProfileService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Every member of the family, sorted by name for a stable list order.
  Stream<List<Profile>> watchMembers() {
    return _db.collection('users').snapshots().map((snap) {
      final people = snap.docs.map(Profile.fromDoc).toList();
      people.sort((a, b) => a.safeName.toLowerCase().compareTo(b.safeName.toLowerCase()));
      return people;
    });
  }

  /// Your own profile, live, so the settings screen can pre-fill your name.
  Stream<Profile?> watchMyProfile(String uid) {
    return _db.collection('users').doc(uid).snapshots().map(
          (snap) => snap.exists ? Profile.fromDoc(snap) : null,
        );
  }

  /// Lets a member change the name other people see.
  ///
  /// Writes keep the email field because the security rules expect the trio
  /// of fields on every profile.
  Future<void> updateDisplayName({
    required String uid,
    required String name,
    required String email,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Name cannot be empty.');
    if (trimmed.length > 60) {
      throw ArgumentError('Name must be 60 characters or fewer.');
    }
    await _db.collection('users').doc(uid).set({
      'displayName': trimmed,
      'email': email,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Makes sure your profile exists. Safe to call on every launch: it is a
  /// no-op once the document is there.
  Future<void> ensureProfile({required String uid, required String email}) async {
    final ref = _db.collection('users').doc(uid);
    final name = _defaultNameFor(email);

    final existing = await ref.get();
    if (existing.exists) {
      final current = Profile.fromDoc(existing);
      if (current.displayName.trim().isNotEmpty) return;
      // Document exists but has no usable name yet - fill it in.
      await ref.set({
        'displayName': name,
        'email': email,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    await ref.set({
      'displayName': name,
      'email': email,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// A friendly starting name, derived from the email local part.
  static String _defaultNameFor(String email) {
    final local = email.split('@').first.trim();
    if (local.isEmpty) return 'Family member';
    return local;
  }

  /// Deterministic id for a 1:1 thread: sorted, so both people land on the
  /// same document whichever order they open it in.
  static String conversationIdFor(String uidA, String uidB) {
    final pair = [uidA, uidB]..sort();
    return pair.join('__');
  }

  /// Creates the conversation document if it is not there yet.
  ///
  /// Called every time a chat is opened. The rules allow rewriting the same
  /// two participants, so calling it repeatedly is harmless. Participants are
  /// stored in sorted order (matching [conversationIdFor]) so the document is
  /// identical no matter which of the two opens it first.
  Future<String> openConversation(String uidA, String uidB) async {
    final id = conversationIdFor(uidA, uidB);
    final pair = [uidA, uidB]..sort();
    await _db.collection('conversations').doc(id).set({
      'participants': pair,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return id;
  }
}
