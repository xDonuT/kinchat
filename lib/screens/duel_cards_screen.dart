import 'package:flutter/material.dart';

import '../models/duel.dart';

class DuelCardsScreen extends StatelessWidget {
  const DuelCardsScreen({super.key, required this.state, required this.myUid});

  final DuelState state;
  final String myUid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final me = state.player(myUid);
    final opponent = state.player(state.otherUid(myUid));

    return Scaffold(
      appBar: AppBar(title: const Text('Cards & decks')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Both starting decks are public. The cards in your hand stay hidden.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (me != null) ...[
            const SizedBox(height: 20),
            _DeckSection(
              title: 'Your deck',
              classId: me.classId,
              deck: duelStarterDeck(classId: me.classId),
            ),
          ],
          if (opponent != null) ...[
            const SizedBox(height: 20),
            _DeckSection(
              title: "Opponent's deck",
              classId: opponent.classId,
              deck: duelStarterDeck(classId: opponent.classId),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'All cards',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Every card currently in the game.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          for (final card in duelCards.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CardInfoTile(card: card),
            ),
        ],
      ),
    );
  }
}

class _DeckSection extends StatelessWidget {
  const _DeckSection({
    required this.title,
    required this.classId,
    required this.deck,
  });

  final String title;
  final String classId;
  final List<String> deck;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duelClass = duelClasses[classId] ?? duelClasses[defaultDuelClassId]!;
    final counts = <String, int>{};
    for (final id in deck) {
      counts[id] = (counts[id] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_classIcon(classId), color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${duelClass.name} · ${deck.length} cards',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final entry in counts.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CardInfoTile(
              card: duelCards[entry.key]!,
              count: entry.value,
            ),
          ),
      ],
    );
  }
}

class _CardInfoTile extends StatelessWidget {
  const _CardInfoTile({required this.card, this.count = 1});

  final DuelCard card;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final attack = card.kind == 'attack';
    final background = attack
        ? scheme.errorContainer
        : scheme.secondaryContainer;
    final foreground = attack
        ? scheme.onErrorContainer
        : scheme.onSecondaryContainer;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: foreground.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: foreground,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${card.cost}',
              style: TextStyle(color: background, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_cardIcon(card), size: 16, color: foreground),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        card.name,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (count > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: foreground.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '×$count',
                          style: TextStyle(
                            color: foreground,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  card.description,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.85),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData _classIcon(String classId) {
  switch (classId) {
    case 'ninja':
      return Icons.flash_on;
    case 'wizard':
      return Icons.auto_awesome;
    case 'knight':
    default:
      return Icons.shield_outlined;
  }
}

IconData _cardIcon(DuelCard card) {
  if (card.poison > 0) return Icons.science_outlined;
  if (card.focus > 0 || card.focusMultiplier > 0) return Icons.auto_awesome;
  return card.kind == 'attack' ? Icons.gavel : Icons.shield_outlined;
}
