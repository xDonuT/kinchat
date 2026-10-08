import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kinchat/main.dart' as app;

/// Drives the real app on a real Android runtime against the Firebase
/// emulator suite, including a genuine two-user round trip: the uncle creates
/// an account and sends a message, signs out, then the nephew creates an
/// account and must see that message arrive.
///
/// Requires:
///   - the emulator suite running (./run-emulator.sh does this)
///   - `flutter test integration_test/app_test.dart -d DEVICE
///       --dart-define=USE_EMULATOR=true --dart-define=EMULATOR_HOST=10.0.2.2`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Emails must be unique per run: the emulator keeps its data between runs.
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final uncleEmail = 'uncle$stamp@test.local';
  final nephewEmail = 'nephew$stamp@test.local';
  const uncleMsg = 'hello from the uncle';
  const nephewReply = 'hi uncle, got it';

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

  /// Prints everything readable on screen so a failed run says *why* instead
  /// of just "0 widgets found".
  Future<void> dumpScreen(WidgetTester tester, String label) async {
    debugPrint('\n===== SCREEN DUMP: $label =====');
    for (final e in find.byType(Text).evaluate()) {
      debugPrint('  TEXT: ${(e.widget as Text).data}');
    }
    for (final e in find.byType(TextFormField).evaluate()) {
      final f = e.widget as TextFormField;
      debugPrint('  FIELD: ${f.controller?.text ?? "<no controller>"}');
    }
    if (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
      debugPrint('  SPINNER: present (still loading)');
    }
    debugPrint('===== END DUMP =====\n');
  }

  Future<void> signOut(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.logout));
    await settle(tester, 800);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await settle(tester, 1500);
  }

  Future<void> sendMessage(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await settle(tester, 300);
    await tester.tap(find.byIcon(Icons.send));
    await settle(tester, 2000);
  }

  /// The landing screen lists chats; open the shared family room from it.
  Future<void> openFamilyChat(WidgetTester tester) async {
    await tester.tap(find.text('Family'));
    await settle(tester, 2000);
  }

  testWidgets('uncle sends, nephew receives', (tester) async {
    app.main();
    await settle(tester, 3000);

    // --- login screen renders ----------------------------------------
    expect(find.text('KinChat'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('TEST MODE -'), findsNothing,
        reason: 'the TEST MODE stripe text is a single banner, not a Text');

    // --- uncle creates an account and sends a message -----------------
    await createAccount(tester, uncleEmail);

    // Registration lands on the chat list; open the family room.
    await openFamilyChat(tester);

    if (find.byIcon(Icons.send).evaluate().isEmpty) {
      await dumpScreen(tester, 'after Create account');
      fail('never reached the chat screen after registering');
    }

    await sendMessage(tester, uncleMsg);
    expect(find.text(uncleMsg), findsOneWidget,
        reason: "the uncle should see his own message");

    // --- sign out, nephew signs up ------------------------------------
    await signOut(tester);
    for (var i = 0; i < 5 && find.text('Sign in').evaluate().isEmpty; i++) {
      await settle(tester, 600);
    }
    if (find.text('Sign in').evaluate().isEmpty) {
      await dumpScreen(tester, 'after sign out (login not found)');
    }
    expect(find.text('Sign in'), findsOneWidget,
        reason: 'sign out should return to the login screen');

    await createAccount(tester, nephewEmail);
    await settle(tester, 2500);
    await openFamilyChat(tester);

    // --- THE REAL TEST: does the message arrive? ----------------------
    expect(find.text(uncleMsg), findsOneWidget,
        reason: 'the nephew must receive the message sent while signed out');

    // --- nephew replies, and both sides are visible -------------------
    await sendMessage(tester, nephewReply);

    expect(find.text(nephewReply), findsOneWidget);
    expect(find.text(uncleMsg), findsOneWidget);

    // Hold the finished conversation on screen so run-e2e.sh can grab a
    // screenshot before it tears the emulator down.
    await Future<void>.delayed(const Duration(seconds: 25));
  });
}