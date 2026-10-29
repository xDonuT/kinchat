import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinchat/services/kuteken_emoji.dart';
import 'package:kinchat/services/kuteken_emoji_data.dart';

void main() {
  test('normalizes variation selectors and resolves mapped emoji', () {
    expect(normalizeKutekenEmoji('❤️'), '❤');
    expect(kutekenAssetFor('❤️'), endsWith('/2764.png'));
    expect(kutekenAssetFor('👍'), isNull);
    expect(hasKutekenEmoji('hi ❤️'), isTrue);
    expect(hasKutekenEmoji('hi 👍'), isFalse);
  });

  testWidgets('renders mapped emoji as images', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: KutekenEmojiText('a 😂 ❤️ 👍'))),
    );
    await tester.pump();

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(2));
    final assets = images
        .map((image) => (image.image as AssetImage).assetName)
        .toSet();
    expect(
      assets,
      containsAll(<String>[kutekenAssetFor('😂')!, kutekenAssetFor('❤️')!]),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not split larger ZWJ sequences', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: KutekenEmojiText('❤️‍🔥'))),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.text('❤‍🔥'), findsOneWidget);
  });

  test('every mapped asset is bundled', () async {
    for (final asset in kutekenEmojiAssets.values) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(0), reason: asset);
    }
  });
}
