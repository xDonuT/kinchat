import 'package:flutter/material.dart';

import '../models/duel.dart';

Future<void> showDuelInfoSheet(
  BuildContext context, {
  required String title,
  required String body,
  required IconData icon,
  Widget? bodyWidget,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (bodyWidget != null)
                bodyWidget
              else
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
                ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showCardInfo(
  BuildContext context, {
  required DuelCard card,
  String? subtitle,
}) {
  return showDuelInfoSheet(
    context,
    title: card.name,
    body: '',
    icon: card.kind == 'attack' ? Icons.gavel : Icons.shield_outlined,
    bodyWidget: _CardInfoBody(card: card, subtitle: subtitle),
  );
}

class _CardInfoBody extends StatelessWidget {
  const _CardInfoBody({required this.card, this.subtitle});

  final DuelCard card;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final attack = card.kind == 'attack';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              attack ? Icons.gavel : Icons.shield_outlined,
              color: scheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                card.name,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          card.description,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
        ),
        const SizedBox(height: 16),
        Text(
          'Details',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _DetailRow('Cost', '${card.cost} energy'),
        _DetailRow('Type', attack ? 'Attack' : 'Skill'),
        if (card.damage > 0)
          _DetailRow(
            'Damage',
            card.focusMultiplier > 0
                ? '${card.damage}, +${card.focusMultiplier} per Focus'
                : '${card.damage}',
          ),
        if (card.block > 0) _DetailRow('Block', '${card.block}'),
        if (card.draw > 0)
          _DetailRow('Draw', '${card.draw} card${card.draw == 1 ? '' : 's'}'),
        if (card.poison > 0)
          _DetailRow('Poison', '${card.poison} (ignores block)'),
        if (card.focus > 0) _DetailRow('Focus', '+${card.focus}'),
        if (card.vulnerable > 0)
          _DetailRow('Vulnerable', '+${card.vulnerable}'),
        if (card.cleanse > 0)
          _DetailRow('Cleanse', 'Removes Poison and Vulnerable from you'),
        if (card.heal > 0) _DetailRow('Heal', '+${card.heal} HP'),
        const SizedBox(height: 16),
        Text(
          _cardTip(card),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String _cardTip(DuelCard card) {
  switch (card.id) {
    case 'strike':
      return 'Reliable basic attack. Good when you have spare energy.';
    case 'defend':
      return 'Block carries over to the opponent’s turn.';
    case 'bash':
      return 'Damage plus Vulnerable; follow-up attacks against the victim hit harder.';
    case 'quick_jab':
      return 'Free chip damage; useful for cycling when you have no energy.';
    case 'iron_wave':
      return 'Attacks and blocks in one card.';
    case 'heavy_blow':
      return 'Big single hit, no defense.';
    case 'shrug_it_off':
      return 'Block plus a card draw; strong early defense.';
    case 'pommel_strike':
      return 'Damage plus draw; efficient tempo.';
    case 'poison_stab':
      return 'Small damage plus Poison; Poison ignores block.';
    case 'deadly_poison':
      return 'Pure Poison; best played early so it has more turns to tick.';
    case 'zap':
      return 'Free permanent Focus; enables bigger Arcane Bolt and Fireball later.';
    case 'mana_shield':
      return 'Block plus permanent Focus.';
    case 'arcane_bolt':
      return 'Cheap Focus payoff; scales with your Focus total.';
    case 'fireball':
      return 'Expensive Focus payoff; big damage if you have stacked Focus.';
    case 'cleanse':
      return 'Removes Poison and Vulnerable from you. Poison ignores block, '
          'so cleanse before it ticks.';
    case 'rest':
      return 'Restores HP directly. Great for sustaining through long matches.';
    case 'strike_plus':
    case 'defend_plus':
    case 'bash_plus':
    case 'quick_jab_plus':
    case 'poison_stab_plus':
    case 'deadly_poison_plus':
    case 'zap_plus':
    case 'arcane_bolt_plus':
    case 'fireball_plus':
      return 'Upgraded class card with boosted stats. Added to your draw pile.';
    default:
      return '';
  }
}
