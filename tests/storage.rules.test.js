/**
 * Storage security rules tests.
 *
 * Runs the REAL storage.rules file against the Firebase Storage emulator.
 * Uploads only need Auth, so no Firestore emulator is required.
 *
 * Run:  node tests/storage.rules.test.js
 */
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  ref,
  uploadBytes,
  getBytes,
  deleteObject,
} = require('firebase/storage');

const RULES = fs.readFileSync(
  path.join(__dirname, '..', 'storage.rules'),
  'utf8',
);

// Pull the member UIDs out of the rules file's isMember() allowlist.
const allowlist = (RULES.match(/request\.auth\.uid in \[([^\]]*)\]/) || [])[1];
const UIDS = allowlist
  ? (allowlist.match(/'[^']+'/g) || []).map((s) => s.slice(1, -1))
  : [];

if (UIDS.length < 2) {
  console.error('error: could not find the isMember() UID allowlist in storage.rules');
  process.exit(2);
}

const [A, B] = UIDS;
const OUTSIDER = 'rAnDoMpErSoN123';
const CONV_AB = [A, B].sort().join('__');
const PHOTO = `conversations/${CONV_AB}/messages/m1.jpg`;
const BYTES = new Uint8Array([0xff, 0xd8, 0xff, 0x00]);

let passed = 0;
const failures = [];

/** The emulator CLI exports HOST as "host:port"; split it for the test env. */
function endpoint(envHost, envPort, fallbackPort) {
  const raw =
    process.env[envHost] || process.env.FIREBASE_STORAGE_EMULATOR_HOST || '';
  const match = /^([^:]+)(?::(\d+))?$/.exec(raw);
  return {
    host: match ? match[1] : '127.0.0.1',
    port: match && match[2]
      ? Number(match[2])
      : Number(process.env[envPort] || fallbackPort),
  };
}

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
  const storage = endpoint(
    'STORAGE_EMULATOR_HOST',
    'STORAGE_EMULATOR_PORT',
    9199,
  );
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-kinchat',
    storage: {
      rules: RULES,
      host: storage.host,
      port: storage.port,
    },
  });

  const storageFor = (uid) =>
    testEnv.authenticatedContext(uid, {}).storage();
  const anon = testEnv.unauthenticatedContext().storage();

  console.log(`\nStorage rules tests (demo-kinchat)\n`);

  await check('a member can upload a photo', () =>
    assertSucceeds(uploadBytes(ref(storageFor(A), PHOTO), BYTES, {
      contentType: 'image/jpeg',
    })));

  await check('another member can read the photo', () =>
    assertSucceeds(getBytes(ref(storageFor(B), PHOTO))));

  await check('a signed-out user cannot read the photo', () =>
    assertFails(getBytes(ref(anon, PHOTO))));

  await check('a signed-out user cannot upload a photo', () =>
    assertFails(uploadBytes(ref(anon, PHOTO), BYTES, {
      contentType: 'image/jpeg',
    })));

  await check('an outsider cannot upload a photo', () =>
    assertFails(uploadBytes(ref(storageFor(OUTSIDER), PHOTO), BYTES, {
      contentType: 'image/jpeg',
    })));

  await check('non-image content is rejected', () =>
    assertFails(uploadBytes(ref(storageFor(A), PHOTO), BYTES, {
      contentType: 'text/plain',
    })));

  await check('photos over 8 MB are rejected', () =>
    assertFails(uploadBytes(
      ref(storageFor(A), PHOTO),
      new Uint8Array(8 * 1024 * 1024 + 1),
      { contentType: 'image/jpeg' },
    )));

  await check('writes outside the chat photo folder are denied', () =>
    assertFails(uploadBytes(ref(storageFor(A), 'elsewhere/photo.jpg'), BYTES, {
      contentType: 'image/jpeg',
    })));

  await check('a member can delete a photo (clear chat)', () =>
    assertSucceeds(deleteObject(ref(storageFor(A), PHOTO))));

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
