import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';

/// Points Auth and Firestore at the local emulator suite.
///
/// Must run before any sign-in or Firestore call. Any data written here is
/// thrown away when the emulator stops, which is the point.
Future<void> connectToEmulators() async {
  if (!useEmulator) {
    debugPrint('EMULATOR: disabled, talking to the real Firebase project');
    return;
  }

  debugPrint(
    'EMULATOR: auth=http://$emulatorHost:$authEmulatorPort '
    'firestore=$emulatorHost:$firestoreEmulatorPort '
    'storage=$emulatorHost:$storageEmulatorPort',
  );

  await FirebaseAuth.instance.useAuthEmulator(emulatorHost, authEmulatorPort);

  FirebaseFirestore.instance.useFirestoreEmulator(
    emulatorHost,
    firestoreEmulatorPort,
  );

  FirebaseStorage.instance.useStorageEmulator(
    emulatorHost,
    storageEmulatorPort,
  );

  // The emulator has no local cache, so keep the app responsive while it is
  // unreachable instead of hanging on every read.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
}

/// Human-readable summary of where the app is pointed, shown in emulator mode
/// so it is obvious you are not touching the real database.
String get emulatorBannerText =>
    'Emulator: $emulatorHost (auth $authEmulatorPort, '
    'firestore $firestoreEmulatorPort, storage $storageEmulatorPort)';
