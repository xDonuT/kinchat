/**
 * Firestore security rules tests.
 *
 * These run against the Firebase Emulator Suite using the REAL firestore.rules
 * file, not a copy. The two placeholder UIDs in that file are treated as
 * literal UIDs here, so the only difference between this test and production
 * is the string values you substitute in step 7 of the README.
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
  collection,
  serverTimestamp,
} = require('firebase/firestore');

// These must match the two strings in firestore.rules.
const A = 'REPLACE_WITH_YOUR_UID';
const B = 'REPLACE_WITH_YOUR_NEPHEWS_UID';
const OUTSIDER = 'rAnDoMpErSoN123';

const MSG = 'chats/main/messages';
const RULES = fs.readFileSync(
  path.join(__dirname, '..', 'firestore.rules'),
  'utf8',
);

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

  console.log('\nFirestore rules tests (demo-kinchat)\n');

  // --- Signed out -----------------------------------------------------
  await check('signed-out user cannot list messages', () =>
    assertFails(getDoc(doc(anon, MSG, 'm1'))));

  await check('signed-out user cannot write a message', () =>
    assertFails(setDoc(doc(anon, MSG, 'm1'), goodMessage)));

  // --- Read access ----------------------------------------------------
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), MSG, 'seed'), goodMessage);
  });

  await check('member A can read messages', () =>
    assertSucceeds(getDoc(doc(dbFor(A), MSG, 'seed'))));

  await check('member B can read messages', () =>
    assertSucceeds(getDoc(doc(dbFor(B), MSG, 'seed'))));

  await check('a signed-in stranger cannot read messages', () =>
    assertFails(getDoc(doc(dbFor(OUTSIDER), MSG, 'seed'))));

  // --- Write access ---------------------------------------------------
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

  // --- Immutability ---------------------------------------------------
  await check('A cannot edit a message after sending it', () =>
    assertFails(setDoc(doc(dbFor(A), MSG, 'fromA'), {
      ...goodMessage,
      text: 'edited',
    })));

  await check('A cannot delete a message', () =>
    assertFails(deleteDoc(doc(dbFor(A), MSG, 'fromA'))));

  await check('B cannot delete a message sent by A', () =>
    assertFails(deleteDoc(doc(dbFor(B), MSG, 'fromA'))));

  // --- Everything else ------------------------------------------------
  await check('a member cannot read user profiles', () =>
    assertFails(getDoc(doc(dbFor(A), 'users', 'anything'))));

  await check('a member cannot write outside the chat', () =>
    assertFails(setDoc(doc(dbFor(A), 'users', 'anything'), { ok: true })));

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