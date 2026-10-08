/**
 * Firestore security rules tests.
 *
 * These run against the Firebase Emulator Suite using the REAL firestore.rules
 * file, not a copy. The member UIDs are read straight out of that file, so the
 * suite always tests exactly what would be deployed - it can never drift.
 *
 * Run:  node tests/rules.test.js
 */
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  setDoc,
  deleteDoc,
  addDoc,
  serverTimestamp,
} = require('firebase/firestore');

const RULES = fs.readFileSync(
  path.join(__dirname, '..', 'firestore.rules'),
  'utf8',
);

// Pull the member UIDs out of the rules file's isMember() allowlist.
const allowlist = (RULES.match(/request\.auth\.uid in \[([^\]]*)\]/) || [])[1];
const UIDS = allowlist ? (allowlist.match(/'[^']+'/g) || []).map((s) => s.slice(1, -1)) : [];

if (UIDS.length < 2) {
  console.error('error: could not find the isMember() UID allowlist in firestore.rules');
  process.exit(2);
}

const [A, B] = UIDS;
const OUTSIDER = 'rAnDoMpErSoN123';

const MSG = 'chats/main/messages';

/** Sorted, so both people compute the same id for the same pair. */
const convId = (x, y) => [x, y].sort().join('__');
const CONV_AB = convId(A, B);
const CONV_AO = convId(A, OUTSIDER);

let passed = 0;
const failures = [];

async function check(name, fn) {
  try {
    await fn();
    passed += 1;
    console.log(`  PASS  ${name}`);
  } catch (err) {
    failures.push({ name, err });
    console.log(`  FAIL  ${name}\n          ${err.message}`);
  }
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-kinchat',
    firestore: {
      rules: RULES,
      host: process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1',
      port: Number(process.env.FIRESTORE_EMULATOR_PORT || 8080),
    },
  });

  const dbFor = (uid) =>
    testEnv.authenticatedContext(uid, {}).firestore();

  const anon = testEnv.unauthenticatedContext().firestore();

  const goodMessage = {
    senderId: A,
    text: 'hello',
    sentAt: serverTimestamp(),
  };

  const profile = (uid) => ({
    displayName: 'Someone',
    email: 'a@b.c',
    updatedAt: serverTimestamp(),
  });

  console.log(`\nFirestore rules tests (demo-kinchat)\n`);
  console.log(`  members: ${UIDS.join(', ')}\n`);

  // === Signed out =====================================================
  await check('signed-out user cannot list messages', () =>
    assertFails(getDoc(doc(anon, MSG, 'm1'))));

  await check('signed-out user cannot write a message', () =>
    assertFails(setDoc(doc(anon, MSG, 'm1'), goodMessage)));

  // === Group chat: read ==============================================
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), MSG, 'seed'), goodMessage);
  });

  await check('member A can read messages', () =>
    assertSucceeds(getDoc(doc(dbFor(A), MSG, 'seed'))));

  await check('member B can read messages', () =>
    assertSucceeds(getDoc(doc(dbFor(B), MSG, 'seed'))));

  await check('a signed-in stranger cannot read messages', () =>
    assertFails(getDoc(doc(dbFor(OUTSIDER), MSG, 'seed'))));

  // === Group chat: write =============================================
  await check('member A can send a message as themselves', () =>
    assertSucceeds(setDoc(doc(dbFor(A), MSG, 'fromA'), goodMessage)));

  await check('member B can send a message as themselves', () =>
    assertSucceeds(setDoc(doc(dbFor(B), MSG, 'fromB'), {
      ...goodMessage,
      senderId: B,
    })));

  await check('A cannot forge a message claiming to be from B', () =>
    assertFails(setDoc(doc(dbFor(A), MSG, 'forged'), {
      ...goodMessage,
      senderId: B,
    })));

  await check('a stranger cannot send a message', () =>
    assertFails(setDoc(doc(dbFor(OUTSIDER), MSG, 'stranger'), {
      ...goodMessage,
      senderId: OUTSIDER,
    })));

  await check('A cannot send an empty message', () =>
    assertFails(setDoc(doc(dbFor(A), MSG, 'empty'), {
      ...goodMessage,
      text: '',
    })));

  await check('A cannot send an oversized message', () =>
    assertFails(setDoc(doc(dbFor(A), MSG, 'huge'), {
      ...goodMessage,
      text: 'x'.repeat(2001),
    })));

  await check('A cannot smuggle extra fields into a message', () =>
    assertFails(setDoc(doc(dbFor(A), MSG, 'sneaky'), {
      ...goodMessage,
      role: 'admin',
    })));

  // === Group chat: immutability ======================================
  await check('A cannot edit a message after sending it', () =>
    assertFails(setDoc(doc(dbFor(A), MSG, 'fromA'), {
      ...goodMessage,
      text: 'edited',
    })));

  await check('A cannot delete a message', () =>
    assertFails(deleteDoc(doc(dbFor(A), MSG, 'fromA'))));

  await check('B cannot delete a message sent by A', () =>
    assertFails(deleteDoc(doc(dbFor(B), MSG, 'fromA'))));

  // === Group reactions ===============================================
  await check('a member can react to a group message', () =>
    assertSucceeds(setDoc(doc(dbFor(A), `${MSG}/fromA/reactions`, A), { emoji: '❤️' })));

  await check('a member can change their own reaction', () =>
    assertSucceeds(setDoc(doc(dbFor(A), `${MSG}/fromA/reactions`, A), { emoji: '😂' })));

  await check('a member can remove their own reaction', () =>
    assertSucceeds(deleteDoc(doc(dbFor(A), `${MSG}/fromA/reactions`, A))));

  await check('a member cannot react on someone else\'s behalf', () =>
    assertFails(setDoc(doc(dbFor(A), `${MSG}/fromA/reactions`, B), { emoji: '❤️' })));

  await check('a reaction cannot carry extra fields', () =>
    assertFails(setDoc(doc(dbFor(A), `${MSG}/fromB/reactions`, A), { emoji: '❤️', note: 'x' })));

  await check('a reaction must have an emoji', () =>
    assertFails(setDoc(doc(dbFor(A), `${MSG}/fromB/reactions`, A), { emoji: '' })));

  await check('a stranger cannot react to a group message', () =>
    assertFails(setDoc(doc(dbFor(OUTSIDER), `${MSG}/seed/reactions`, OUTSIDER), { emoji: '❤️' })));

  // === Profiles =======================================================
  await check('a member can read another member\'s profile', () =>
    assertSucceeds(getDoc(doc(dbFor(B), 'users', A))));

  await check('a member can create their own profile', () =>
    assertSucceeds(setDoc(doc(dbFor(A), 'users', A), profile(A))));

  await check('a member can update their own profile', () =>
    assertSucceeds(setDoc(doc(dbFor(A), 'users', A), {
      ...profile(A),
      displayName: 'Renamed',
    })));

  await check('a member cannot write someone else\'s profile', () =>
    assertFails(setDoc(doc(dbFor(A), 'users', B), profile(B))));

  await check('a profile cannot carry unexpected fields', () =>
    assertFails(setDoc(doc(dbFor(A), 'users', A), {
      ...profile(A),
      isAdmin: true,
    })));

  await check('a profile cannot have an empty display name', () =>
    assertFails(setDoc(doc(dbFor(A), 'users', A), {
      ...profile(A),
      displayName: '',
    })));

  await check('a stranger cannot read profiles', () =>
    assertFails(getDoc(doc(dbFor(OUTSIDER), 'users', A))));

  await check('a stranger cannot write profiles', () =>
    assertFails(setDoc(doc(dbFor(OUTSIDER), 'users', OUTSIDER), profile(OUTSIDER))));

  await check('a member cannot delete a profile', () =>
    assertFails(deleteDoc(doc(dbFor(A), 'users', A))));

  // === 1:1 conversations =============================================
  await check('A can open a 1:1 conversation with B', () =>
    assertSucceeds(setDoc(doc(dbFor(A), 'conversations', CONV_AB), {
      participants: [A, B],
      updatedAt: serverTimestamp(),
    })));

  await check('opening the same 1:1 again is idempotent', () =>
    assertSucceeds(setDoc(doc(dbFor(B), 'conversations', CONV_AB), {
      participants: [A, B],
      updatedAt: serverTimestamp(),
    })));

  await check('A can send a private message', () =>
    assertSucceeds(setDoc(doc(dbFor(A), `conversations/${CONV_AB}/messages`, 'm1'), {
      senderId: A,
      text: 'psst',
      sentAt: serverTimestamp(),
    })));

  await check('B can read the private message', () =>
    assertSucceeds(getDoc(doc(dbFor(B), `conversations/${CONV_AB}/messages`, 'm1'))));

  await check('B can reply in the private thread', () =>
    assertSucceeds(setDoc(doc(dbFor(B), `conversations/${CONV_AB}/messages`, 'm2'), {
      senderId: B,
      text: 'hi back',
      sentAt: serverTimestamp(),
    })));

  await check('a stranger cannot read a 1:1 conversation', () =>
    assertFails(getDoc(doc(dbFor(OUTSIDER), `conversations/${CONV_AB}/messages`, 'm1'))));

  await check('a stranger cannot write into a 1:1 conversation', () =>
    assertFails(setDoc(doc(dbFor(OUTSIDER), `conversations/${CONV_AB}/messages`, 'm3'), {
      senderId: OUTSIDER,
      text: 'intruder',
      sentAt: serverTimestamp(),
    })));

  await check('a member cannot forge a message in a 1:1', () =>
    assertFails(setDoc(doc(dbFor(A), `conversations/${CONV_AB}/messages`, 'forged'), {
      senderId: B,
      text: 'not me',
      sentAt: serverTimestamp(),
    })));

  // === Missing conversation documents ================================
  await check('reading a 1:1 thread before its conversation doc exists is allowed (returns empty)', () =>
    assertSucceeds(getDoc(doc(dbFor(A), 'conversations', 'uncreated_thread_zz', 'messages', 'ghost'))));

  await check('writing into a 1:1 thread with no conversation doc is denied', () =>
    assertFails(setDoc(doc(dbFor(A), `conversations/uncreated_thread_zz/messages`, 'm1'), {
      senderId: A,
      text: 'nope',
      sentAt: serverTimestamp(),
    })));

  // === 1:1 reactions =================================================
  await check('A can react to a private message', () =>
    assertSucceeds(setDoc(doc(dbFor(A), `conversations/${CONV_AB}/messages/m1/reactions`, A), { emoji: '👍' })));

  await check('B can react to the same private message', () =>
    assertSucceeds(setDoc(doc(dbFor(B), `conversations/${CONV_AB}/messages/m1/reactions`, B), { emoji: '🔥' })));

  await check('A cannot react as B in the private thread', () =>
    assertFails(setDoc(doc(dbFor(A), `conversations/${CONV_AB}/messages/m1/reactions`, B), { emoji: '🔥' })));

  await check('a non-participant cannot react in a 1:1', () =>
    assertFails(setDoc(doc(dbFor(OUTSIDER), `conversations/${CONV_AB}/messages/m1/reactions`, OUTSIDER), { emoji: '🔥' })));

  // A conversation between A and a non-member must be invisible to B.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'conversations', CONV_AO), {
      participants: [A, OUTSIDER],
      updatedAt: serverTimestamp(),
    });
    await setDoc(
      doc(ctx.firestore(), `conversations/${CONV_AO}/messages`, 'secret'),
      { senderId: A, text: 'not for B', sentAt: serverTimestamp() },
    );
  });

  await check('B cannot read a 1:1 they are not part of', () =>
    assertFails(getDoc(doc(dbFor(B), `conversations/${CONV_AO}/messages`, 'secret'))));

  await check('the outsider cannot read their own conversation either', () =>
    assertFails(getDoc(doc(dbFor(OUTSIDER), `conversations/${CONV_AO}/messages`, 'secret'))));

  await check('participants can never be swapped after creation', () =>
    assertFails(setDoc(doc(dbFor(A), 'conversations', CONV_AB), {
      participants: [A, OUTSIDER],
      updatedAt: serverTimestamp(),
    })));

  await check('a stranger cannot create a conversation', () =>
    assertFails(setDoc(doc(dbFor(OUTSIDER), 'conversations', convId(OUTSIDER, B)), {
      participants: [OUTSIDER, B],
      updatedAt: serverTimestamp(),
    })));

  // === Everything else ===============================================
  await check('a member cannot write outside the known collections', () =>
    assertFails(setDoc(doc(dbFor(A), 'anything', 'else'), { ok: true })));

  await check('a member cannot write to a different chat id', () =>
    assertFails(setDoc(doc(dbFor(A), 'chats/other/messages', 'm1'), {
      ...goodMessage,
    })));

  await check('a member cannot add to a subcollection of a message', () =>
    assertFails(setDoc(doc(dbFor(A), 'chats/main/messages/fromA/replies', 'r1'), {
      text: 'hi',
    })));

  console.log(
    `\n${passed} passed, ${failures.length} failed, ` +
      `${passed + failures.length} total\n`,
  );

  await testEnv.cleanup();
  process.exit(failures.length === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error('\nTest harness crashed:\n', err);
  process.exit(2);
});
