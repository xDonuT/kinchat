const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// The family. When you add a family member, add them here AND in
// firestore.rules (the app only allows people on that list to sign in).
const MEMBER_UID_TO_NAME = {
  '3Dg3UMznaWTjrpodHCokaPkjEEt1': 'jhazzymae89',
  'LKiCZKuQRPf3BL3NsnSDcRYIKjH2': 'donutbud',
  'BWBzQQl3GCeL8w9tjAY0cyxkzcB2': 'matmat',
  'cCMfAF6iowWGHdDN5QYRYabe0ng1': 'tantan',
  'CCQve7XDMBf5srFmzUeJXolsIj92': 'miky',
  'Wj7CjQLG5QMkc0eziwG8F7XB52p2': 'orange123',
};

async function tokensFor(uid) {
  try {
    const snap = await db
      .collection('users')
      .doc(uid)
      .collection('tokens')
      .get();
    return snap.docs.map((d) => d.data().token).filter(Boolean);
  } catch (err) {
    console.warn('tokensFor failed', uid, err.message);
    return [];
  }
}

async function removeInvalidTokens(unregistered) {
  if (!unregistered.size) return;
  try {
    const snap = await db
      .collectionGroup('tokens')
      .where('token', 'in', [...unregistered])
      .get();
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  } catch (err) {
    console.warn('token cleanup failed', err.message);
  }
}

async function push(tokens, title, body, data) {
  const uniq = [...new Set(tokens)];
  if (!uniq.length) return;
  try {
    const result = await messaging.sendEachForMulticast({
      tokens: uniq,
      notification: { title, body },
      data: Object.assign({ title, body }, data),
      android: { priority: 'high' },
    });
    const invalid = new Set();
    result.responses.forEach((r, i) => {
      if (!r.success) invalid.add(uniq[i]);
    });
    await removeInvalidTokens(invalid);
  } catch (err) {
    console.warn('push failed', err.message);
  }
}

async function senderName(sender) {
  return MEMBER_UID_TO_NAME[sender] || 'KinChat';
}

// A private 1:1 message: tell the other participant that a message arrived.
// The sender's text goes in the notification body so it appears without
// opening the app.
exports.onPrivateMessageCreated = onDocumentCreated(
  'conversations/{convId}/messages/{messageId}',
  async (event) => {
    const message = event.data.data();
    const convId = event.params.convId;
    const sender = message && message.senderId;
    const isPhoto = message && (message.type === 'image' || !!message.imageUrl);
    const isGame = message && message.type === 'game';
    if (!sender || (!message.text && !isPhoto && !isGame)) return;

    const conv = await db.collection('conversations').doc(convId).get();
    if (!conv.exists) return;
    const participants = conv.data().participants || [];
    const others = participants.filter((p) => p !== sender);
    const needle = await senderName(sender);
    const body = isGame
      ? '\u{1F3AE} Duel invite'
      : isPhoto
      ? '\u{1F4F7} Photo'
      : message.text;

    for (const uid of others) {
      const tokens = await tokensFor(uid);
      await push(tokens, needle, body, {
        room: 'private',
        roomId: convId,
        type: isGame ? 'game' : isPhoto ? 'image' : 'text',
      });
    }
  },
);