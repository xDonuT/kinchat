import 'package:flutter/material.dart';

import '../models/duel.dart';
import '../services/chat_service.dart';
import '../services/duel_service.dart';

class DuelScreen extends StatefulWidget {
  const DuelScreen({
    super.key,
    required this.room,
    required this.gameId,
    required this.myUid,
    required this.myName,
    required this.opponentName,
  });

  final ChatRoom room;
  final String gameId;
  final String myUid;
  final String myName;
  final String opponentName;

  @override
  State<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends State<DuelScreen> {
  final DuelService _service = DuelService();
  bool _busy = false;

  Future<void> _playCard(int index) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _service.playCard(
        room: widget.room,
        gameId: widget.gameId,
        uid: widget.myUid,
        handIndex: index,
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _endTurn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _service.endTurn(
        room: widget.room,
        gameId: widget.gameId,
        uid: widget.myUid,
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restart() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _service.restartDuel(
        room: widget.room,
        gameId: widget.gameId,
        uid: widget.myUid,
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$error')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Duel')),
      body: StreamBuilder<DuelState?>(
        stream: _service.watchDuel(widget.room, widget.gameId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load duel.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final state = snapshot.data;
          if (state == null) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            return const Center(child: Text('Duel unavailable.'));
          }

          final me = state.player(widget.myUid);
          final opponent = state.player(state.otherUid(widget.myUid));
          if (me == null || opponent == null) {
            return const Center(child: Text('Duel unavailable.'));
          }

          final myTurn = state.isActive && state.turn == widget.myUid;

          return SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    children: [
                      _PlayerPanel(
                        name: widget.opponentName,
                        player: opponent,
                        isTurn: state.isActive && state.turn == opponent.uid,
                      ),
                      const SizedBox(height: 12),
                      _StatusBanner(
                        state: state,
                        myUid: widget.myUid,
                        opponentName: widget.opponentName,
                      ),
                      const SizedBox(height: 12),
                      _PlayerPanel(
                        name: widget.myName,
                        player: me,
                        isTurn: myTurn,
                      ),
                      const SizedBox(height: 16),
                      _LogPanel(
                        state: state,
                        myUid: widget.myUid,
                        myName: widget.myName,
                        opponentName: widget.opponentName,
                      ),
                    ],
                  ),
                ),
                _HandPanel(
                  state: state,
                  player: me,
                  myTurn: myTurn,
                  busy: _busy,
                  opponentName: widget.opponentName,
                  onPlay: _playCard,
                  onEndTurn: _endTurn,
                  onRestart: _restart,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel({
    required this.name,
    required this.player,
    required this.isTurn,
  });

  final String name;
  final DuelPlayer player;
  final bool isTurn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duelClass =
        duelClasses[player.classId] ?? duelClasses[defaultDuelClassId]!;
    final hpRatio = player.maxHp <= 0
        ? 0.0
        : (player.hp / player.maxHp).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isTurn
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isTurn ? scheme.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (isTurn)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Turn',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Text('HP ${player.hp}/${player.maxHp}'),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: hpRatio,
              minHeight: 8,
              backgroundColor: scheme.surface,
              color: hpRatio > 0.5
                  ? scheme.primary
                  : hpRatio > 0.25
                  ? Colors.orange
                  : scheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _StatChip(
                icon: _classIcon(player.classId),
                label: duelClass.name,
              ),
              _StatChip(
                icon: Icons.shield_outlined,
                label: 'Block ${player.block}',
              ),
              _StatChip(
                icon: Icons.bolt,
                label: 'Energy ${player.energy}/${player.maxEnergy}',
              ),
              if (player.vulnerable > 0)
                _StatChip(
                  icon: Icons.warning_amber_rounded,
                  label: 'Vulnerable ${player.vulnerable}',
                ),
              if (player.poison > 0)
                _StatChip(
                  icon: Icons.science_outlined,
                  label: 'Poison ${player.poison}',
                ),
              if (player.focus > 0)
                _StatChip(
                  icon: Icons.auto_awesome,
                  label: 'Focus ${player.focus}',
                ),
              _StatChip(
                icon: Icons.style_outlined,
                label: 'Hand ${player.handCount}',
              ),
            ],
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

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.state,
    required this.myUid,
    required this.opponentName,
  });

  final DuelState state;
  final String myUid;
  final String opponentName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final finished = state.isFinished;
    final won = state.winner == myUid;
    final text = finished
        ? (won ? 'You win!' : '$opponentName wins!')
        : (state.turn == myUid ? 'Your turn' : '$opponentName\'s turn');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: finished
            ? (won ? scheme.primaryContainer : scheme.errorContainer)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            finished ? (won ? Icons.emoji_events : Icons.close) : Icons.circle,
            color: finished
                ? (won ? scheme.onPrimaryContainer : scheme.onErrorContainer)
                : scheme.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text('Round ${state.round}'),
        ],
      ),
    );
  }
}

class _LogPanel extends StatelessWidget {
  const _LogPanel({
    required this.state,
    required this.myUid,
    required this.myName,
    required this.opponentName,
  });

  final DuelState state;
  final String myUid;
  final String myName;
  final String opponentName;

  @override
  Widget build(BuildContext context) {
    final entries = state.log.reversed.take(8).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Combat log',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        if (entries.isEmpty)
          Text(
            'No actions yet.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                entry.uid.isEmpty
                    ? entry.text
                    : '${_nameFor(entry.uid)} ${entry.text}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: entry.uid.isEmpty
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : entry.uid == myUid
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.tertiary,
                  fontWeight: entry.uid.isEmpty
                      ? FontWeight.normal
                      : FontWeight.w600,
                ),
              ),
            ),
      ],
    );
  }

  String _nameFor(String uid) {
    if (uid == myUid) return myName;
    return opponentName;
  }
}

class _HandPanel extends StatelessWidget {
  const _HandPanel({
    required this.state,
    required this.player,
    required this.myTurn,
    required this.busy,
    required this.opponentName,
    required this.onPlay,
    required this.onEndTurn,
    required this.onRestart,
  });

  final DuelState state;
  final DuelPlayer player;
  final bool myTurn;
  final bool busy;
  final String opponentName;
  final ValueChanged<int> onPlay;
  final VoidCallback onEndTurn;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (state.isFinished) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            const Expanded(child: Text('Duel finished')),
            FilledButton.icon(
              onPressed: busy ? null : onRestart,
              icon: const Icon(Icons.replay),
              label: const Text('Rematch'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 138,
            child: player.hand.isEmpty
                ? Center(
                    child: Text(
                      'No cards in hand.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: player.hand.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final card = duelCards[player.hand[index]];
                      if (card == null) return const SizedBox.shrink();
                      return _DuelCardTile(
                        card: card,
                        enabled: myTurn && !busy,
                        onTap: () => onPlay(index),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  myTurn ? 'Your turn' : 'Waiting for $opponentName...',
                  style: TextStyle(
                    color: myTurn ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: myTurn && !busy ? onEndTurn : null,
                icon: const Icon(Icons.skip_next),
                label: const Text('End turn'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DuelCardTile extends StatelessWidget {
  const _DuelCardTile({
    required this.card,
    required this.enabled,
    required this.onTap,
  });

  final DuelCard card;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final attack = card.kind == 'attack';
    final icon = card.poison > 0
        ? Icons.science_outlined
        : card.focus > 0 || card.focusMultiplier > 0
        ? Icons.auto_awesome
        : attack
        ? Icons.gavel
        : Icons.shield_outlined;
    final background = attack
        ? scheme.errorContainer
        : scheme.secondaryContainer;
    final foreground = attack
        ? scheme.onErrorContainer
        : scheme.onSecondaryContainer;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: SizedBox(
        width: 116,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: foreground,
                        child: Text(
                          '${card.cost}',
                          style: TextStyle(
                            color: background,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Icon(icon, size: 16, color: foreground),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    card.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(
                      card.description,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.85),
                        fontSize: 10,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
