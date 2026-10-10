import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kinchat/main.dart' as app;

/// Drives the real app on a real Android runtime against the Firebase
/// emulator suite. Verifies the family room is gone and that the app now
/// offers only 1:1 chats, with friend-adding living in Settings.
///
/// Requires:
///   - the emulator suite running (./run-emulator.sh does this)
///   - `flutter test integration_test/app_test.dart -d DEVICE
///       --dart-define=USE_EMULATOR=true --dart-define=EMULATOR_HOST=10.0.2.2`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Emails must be unique per run: the emulator keeps its data between runs.
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final email = 'solo$stamp@test.local';

  /// Network work against the emulator is not tied to frames, so pumpAndSettle
  /// alone returns too early. Mix in real delays.
  Future<void> settle(WidgetTester tester, [int ms = 1200]) async {
    await tester.pumpAndSettle();
    await Future<void>.delayed(Duration(milliseconds: ms));
    await tester.pumpAndSettle();
  }

  Future<void> fillCredentials(WidgetTester tester, String email) async {
    await tester.enterText(find.byType(TextFormField).at(0), email);
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await settle(tester, 300);
  }

  Future<void> createAccount(WidgetTester tester, String email) async {
    await tester.tap(find.text('First time here? Create an account'));
    await settle(tester, 600);
    await fillCredentials(tester, email);
    await tester.tap(find.text('Create account'));
    await settle(tester, 2500);
  }

  testWidgets('home has 1:1 chats only, no family room', (tester) async {
    app.main();
    await settle(tester, 3000);

    // --- login screen renders ----------------------------------------
    expect(find.text('KinChat'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);

    // --- register and land on the home screen -------------------------
    await createAccount(tester, email);

    // The shared family room must be gone; only 1:1 chats remain.
    expect(find.text('FAMILY'), findsNothing);
    expect(find.text('Everyone'), findsNothing);
    expect(find.text('CHATS'), findsOneWidget);

    // Adding a friend now lives in Settings, and the family controls are gone.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await settle(tester, 1200);
    expect(find.text('Add a friend'), findsOneWidget);
    expect(find.text('Delete the family'), findsNothing);
    expect(find.text('FAMILY'), findsNothing);
  });
}
