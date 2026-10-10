import 'package:cloud_firestore/cloud_firestore.dart';

/// The relationship between you and one other member.
class ContactLink {
  const ContactLink({
    required this.uid,
    required this.status,
    required this.requestedBy,
  });

  /// The other person's UID.
  final String uid;

  /// 'pending' until the other person accepts, then 'accepted'.
  final String status;

  /// Who sent the request.
  final String requestedBy;

  bool get accepted => status == 'accepted';

  /// They asked to add you and you have not answered yet.
  bool incomingRequest(String me) => status == 'pending' && requestedBy != me;

  /// You asked to add them and they have not answered yet.
  bool outgoingRequest(String me) => status == 'pending' && requestedBy == me;
}

/// Friend requests and accepted contacts.
///
/// A contact lives in a single shared `contacts/{pairId}` document, so both
/// people read the same record and the security rules can enforce that only
/// the *other* person may flip a request from pending to accepted.
class ContactsService {
  ContactsService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _contacts =>
      _db.collection('contacts');

  /// Same sorted pair id the 1:1 conversation uses, so the two stay in step.
  static String pairIdFor(String a, String b) {
    final pair = [a, b]..sort();
    return pair.join('__');
  }

  /// Every contact relationship you are part of (pending or accepted).
  Stream<List<ContactLink>> watch(String me) => _contacts
      .where('participants', arrayContains: me)
      .snapshots()
      .map((snap) => [
            for (final doc in snap.docs)
              ContactLink(
                uid: (doc['participants'] as List)
                    .cast<String>()
                    .firstWhere((p) => p != me, orElse: () => me),
                status: doc['status'] as String,
                requestedBy: doc['requestedBy'] as String,
              ),
          ]);

  /// Ask to add [other]. They must accept before either can chat.
  Future<void> request(String me, String other) =>
      _contacts.doc(pairIdFor(me, other)).set({
        'participants': [me, other]..sort(),
        'requestedBy': me,
        'status': 'pending',
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Accept the request [other] sent you.
  Future<void> accept(String me, String other) =>
      _contacts.doc(pairIdFor(me, other)).update({
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Decline their request, cancel yours, or remove an accepted contact.
  Future<void> remove(String me, String other) =>
      _contacts.doc(pairIdFor(me, other)).delete();
}
