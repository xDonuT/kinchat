# kinchat

A small private family chat app built with Flutter and Firebase.

## Sending photos

Photos are chosen from the gallery, scaled to at most 1600 px, re-encoded as
JPEG on the device (quality 80), and uploaded to Firebase Storage under
`conversations/<convId>/messages/<messageId>.jpg`. Only then is the Firestore
message written, so the chat stream never sees a photo that is still uploading.

To enable it on the real project (`kinchat-c9057`):

1. Firebase console -> Storage -> Get started (the Blaze plan is required).
2. Deploy the rules and the notification function:

   ```sh
   firebase deploy --only firestore:rules,storage,functions --project kinchat-c9057
   ```

3. Rebuild the app (`flutter build apk` or `flutter run`).

The Flutter app needs the `firebase_storage` package; run `flutter pub get`
after pulling.

## Local emulator

The emulator suite now includes Storage on port 9199:

```sh
firebase emulators:start --config firebase.dev.json --project demo-kinchat
flutter run --dart-define=USE_EMULATOR=true
```

## Rules tests

With the emulators running and the test dependencies installed:

```sh
node tests/rules.test.js
node tests/storage.rules.test.js
```
