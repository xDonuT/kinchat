import 'package:flutter/material.dart';

import '../models/duel.dart';
import '../services/chat_service.dart';
import '../services/duel_service.dart';
import '../services/duel_sfx.dart';
import '../widgets/duel_info_sheet.dart';
import 'duel_cards_screen.dart';

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
  late bool _soundEnabled;
  bool _outcomeAnnounced = false;
  DuelState? _latestState;

  @override
  void initState() {
    super.initState();
    _soundEnabled = DuelSfx.instance.enabled;
  }

  @override
  void dispose() {
    DuelSfx.instance.stop();
    super.dispose();
  }

  Future<void> _playCard(int index, DuelCard card) async {
    if (_busy) return;
    DuelSfx.instance.play(card.kind == 'attack' ? 'hit' : 'card');
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
    DuelSfx.instance.play('turn');
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

  Future<void> _onRewardDraft(String cardId) async {
    if (_busy) return;
    DuelSfx.instance.play('card');
    setState(() => _busy = true);
    try {
      await _service.takeRewardDraft(
        room: widget.room,
        gameId: widget.gameId,
        uid: widget.myUid,
        cardId: cardId,
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseClass(String classId) async {
    if (_busy) return;
    DuelSfx.instance.play('card');
    setState(() => _busy = true);
    try {
      await _service.chooseClass(
        room: widget.room,
        gameId: widget.gameId,
        uid: widget.myUid,
        classId: classId,
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setReady(bool ready) async {
    if (_busy) return;
    DuelSfx.instance.play(ready ? 'turn' : 'card');
    setState(() => _busy = true);
    try {
      await _service.setReady(
        room: widget.room,
        gameId: widget.gameId,
        uid: widget.myUid,
        ready: ready,
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openCards() {
    final state = _latestState;
    if (state == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DuelCardsScreen(state: state, myUid: widget.myUid),
      ),
    );
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$error')));
  }

  void _toggleSound() {
    final enabled = !_soundEnabled;
    setState(() => _soundEnabled = enabled);
    DuelSfx.instance.setEnabled(enabled);
    if (!enabled) DuelSfx.instance.stop();
  }

  void _announceOutcome(DuelState state) {
    if (state.isLobby || state.isActive) {
      _outcomeAnnounced = false;
      return;
    }
    if (!state.isFinished || _outcomeAnnounced) return;
    _outcomeAnnounced = true;
    DuelSfx.instance.play(state.winner == widget.myUid ? 'win' : 'lose');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duel'),
        actions: [
          IconButton(
            tooltip: 'Card library',
            onPressed: _openCards,
            icon: const Icon(Icons.menu_book_outlined),
          ),
          IconButton(
            tooltip: _soundEnabled ? 'Mute sounds' : 'Enable sounds',
            onPressed: _toggleSound,
            icon: Icon(_soundEnabled ? Icons.volume_up : Icons.volume_off),
          ),
        ],
      ),
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

          _latestState = state;
          _announceOutcome(state);
          if (state.isLobby) {
            return _LobbyView(
              state: state,
              myUid: widget.myUid,
              myName: widget.myName,
              opponentName: widget.opponentName,
              busy: _busy,
              onChooseClass: _chooseClass,
              onReadyChanged: _setReady,
            );
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
                  onRewardDraft: _onRewardDraft,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LobbyView extends StatelessWidget {
  const _LobbyView({
    required this.state,
    required this.myUid,
    required this.myName,
    required this.opponentName,
    required this.busy,
    required this.onChooseClass,
    required this.onReadyChanged,
  });

  final DuelState state;
  final String myUid;
  final String myName;
  final String opponentName;
  final bool busy;
  final ValueChanged<String> onChooseClass;
  final ValueChanged<bool> onReadyChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final me = state.player(myUid);
    final opponent = state.player(state.otherUid(myUid));
    if (me == null || opponent == null) {
      return const Center(child: Text('Duel unavailable.'));
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Duel lobby',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose your class, then ready up. The duel starts when both players are ready.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _LobbyPlayerCard(name: myName, player: me, isMe: true),
          const SizedBox(height: 8),
          _LobbyPlayerCard(name: opponentName, player: opponent, isMe: false),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Choose your class',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (me.ready)
                Text(
                  'Cancel ready to change',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final duelClass in duelClasses.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LobbyClassTile(
                duelClass: duelClass,
                selected: me.classId == duelClass.id,
                enabled: !busy && !me.ready,
                onTap: () => onChooseClass(duelClass.id),
              ),
            ),
          const SizedBox(height: 8),
          if (me.ready)
            OutlinedButton.icon(
              onPressed: busy ? null : () => onReadyChanged(false),
              icon: const Icon(Icons.close),
              label: const Text('Cancel ready'),
            )
          else
            FilledButton.icon(
              onPressed: busy ? null : () => onReadyChanged(true),
              icon: const Icon(Icons.check),
              label: const Text('Ready'),
            ),
          const SizedBox(height: 8),
          Text(
            me.ready
                ? (opponent.ready
                      ? 'Both ready. Starting...'
                      : 'Waiting for $opponentName...')
                : (opponent.ready
                      ? '$opponentName is ready.'
                      : 'You are not ready yet.'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: me.ready ? scheme.primary : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${state.turn == myUid ? 'You start' : '$opponentName starts'} when the duel begins.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _LobbyPlayerCard extends StatelessWidget {
  const _LobbyPlayerCard({
    required this.name,
    required this.player,
    required this.isMe,
  });

  final String name;
  final DuelPlayer player;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duelClass =
        duelClasses[player.classId] ?? duelClasses[defaultDuelClassId]!;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: player.ready ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: scheme.surface,
            child: Icon(_classIcon(player.classId), color: scheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '$name (you)' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${duelClass.name} · ${duelClass.maxHp} HP',
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: player.ready ? scheme.primary : scheme.surface,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              player.ready ? 'Ready' : 'Choosing',
              style: TextStyle(
                color: player.ready
                    ? scheme.onPrimary
                    : scheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LobbyClassTile extends StatelessWidget {
  const _LobbyClassTile({
    required this.duelClass,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final DuelClass duelClass;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurface;

    return Opacity(
      opacity: enabled ? 1 : 0.7,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.surface,
                  child: Icon(_classIcon(duelClass.id), color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              duelClass.name,
                              style: TextStyle(
                                color: foreground,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '${duelClass.maxHp} HP',
                            style: TextStyle(
                              color: foreground.withValues(alpha: 0.8),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        duelClass.description,
                        style: TextStyle(
                          color: foreground.withValues(alpha: 0.8),
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle, color: scheme.primary),
                ],
              ],
            ),
          ),
        ),
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
                onTap: () => showDuelInfoSheet(
                  context,
                  title: duelClass.name,
                  icon: _classIcon(player.classId),
                  body:
                      '${duelClass.description}\n\n'
                      'HP: ${duelClass.maxHp}\n'
                      'Energy: ${duelClass.maxEnergy}\n'
                      'Starting deck: 10 cards',
                ),
              ),
              _StatChip(
                icon: Icons.shield_outlined,
                label: 'Block ${player.block}',
                onTap: () => showDuelInfoSheet(
                  context,
                  title: 'Block ${player.block}',
                  icon: Icons.shield_outlined,
                  body:
                      'Block absorbs attack damage before HP.\n\n'
                      'It protects through the opponent\'s turn, then clears '
                      'at the start of $name\'s next turn.\n\n'
                      'Current: ${player.block} block.',
                ),
              ),
              _StatChip(
                icon: Icons.bolt,
                label: 'Energy ${player.energy}/${player.maxEnergy}',
                onTap: () => showDuelInfoSheet(
                  context,
                  title: 'Energy ${player.energy}/${player.maxEnergy}',
                  icon: Icons.bolt,
                  body:
                      'Energy is spent to play cards. It refills to '
                      '${player.maxEnergy} at the start of $name\'s turn.\n\n'
                      'Unspent energy is lost when the turn ends.\n\n'
                      'Current: ${player.energy}/${player.maxEnergy}.',
                ),
              ),
              if (player.vulnerable > 0)
                _StatChip(
                  icon: Icons.warning_amber_rounded,
                  label: 'Vulnerable ${player.vulnerable}',
                  onTap: () => showDuelInfoSheet(
                    context,
                    title: 'Vulnerable ${player.vulnerable}',
                    icon: Icons.warning_amber_rounded,
                    body:
                        'Attacks against $name deal 50% more damage, rounded '
                        'down.\n\n'
                        'Each point drops by 1 at the end of $name\'s turn. '
                        'It stacks.\n\n'
                        'Current: ${player.vulnerable} Vulnerable.',
                  ),
                ),
              if (player.poison > 0)
                _StatChip(
                  icon: Icons.science_outlined,
                  label: 'Poison ${player.poison}',
                  onTap: () => showDuelInfoSheet(
                    context,
                    title: 'Poison ${player.poison}',
                    icon: Icons.science_outlined,
                    body: _poisonBody(name, player.poison),
                  ),
                ),
              if (player.focus > 0)
                _StatChip(
                  icon: Icons.auto_awesome,
                  label: 'Focus ${player.focus}',
                  onTap: () => showDuelInfoSheet(
                    context,
                    title: 'Focus ${player.focus}',
                    icon: Icons.auto_awesome,
                    body:
                        'Focus is permanent and does not expire at the end of '
                        'the turn.\n\n'
                        'Cards that say "per Focus" gain that much extra '
                        'damage for each Focus.\n\n'
                        'Current: ${player.focus} Focus.',
                  ),
                ),
              _StatChip(
                icon: Icons.style_outlined,
                label: 'Hand ${player.handCount}',
                onTap: () => showDuelInfoSheet(
                  context,
                  title: 'Hand ${player.handCount}',
                  icon: Icons.style_outlined,
                  body:
                      'Cards currently in $name\'s hand.\n\n'
                      'Draw 5 at the start of your turn, up to 10. Remaining '
                      'cards are discarded at the end of the turn.\n\n'
                      'Current: ${player.handCount} cards.',
                ),
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

String _poisonBody(String name, int poison) {
  final ticks = List.generate(
    poison,
    (index) => '${poison - index}',
  ).join(' → ');
  final total = poison * (poison + 1) ~/ 2;
  return 'At the start of $name\'s turn, they take damage equal to Poison, '
      'ignoring block. Then Poison drops by 1.\n\n'
      'Next ticks: $ticks damage.\n'
      'If it runs its course: $total total damage.\n\n'
      'Current: $poison Poison.';
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(999));
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          if (onTap != null) ...[
            const SizedBox(width: 3),
            Icon(Icons.info_outline, size: 12, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return Container(
        decoration: BoxDecoration(color: scheme.surface, borderRadius: radius),
        child: content,
      );
    }

    return Material(
      color: scheme.surface,
      borderRadius: radius,
      child: InkWell(onTap: onTap, borderRadius: radius, child: content),
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
    final scheme = Theme.of(context).colorScheme;
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
                      ? scheme.onSurfaceVariant
                      : _logColor(
                          scheme,
                          entry.uid == myUid ? scheme.primary : scheme.tertiary,
                        ),
                  fontWeight: entry.uid.isEmpty
                      ? FontWeight.normal
                      : FontWeight.w600,
                ),
              ),
            ),
      ],
    );
  }

  Color _logColor(ColorScheme scheme, Color color) {
    if (scheme.brightness == Brightness.dark) return color;
    return Color.lerp(color, Colors.black, 0.45)!;
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
    required this.onRewardDraft,
  });

  final DuelState state;
  final DuelPlayer player;
  final bool myTurn;
  final bool busy;
  final String opponentName;
  final void Function(int index, DuelCard card) onPlay;
  final VoidCallback onEndTurn;
  final VoidCallback onRestart;
  final void Function(String cardId) onRewardDraft;

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

    final myUid = player.uid;
    final canDraft = state.isActive &&
        state.round % 3 == 0 &&
        state.round > state.draftRound &&
        !state.draftPicks.containsKey(myUid);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canDraft) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: busy ? null : () => _showDraftPicker(context),
                  icon: const Icon(Icons.card_giftcard),
                  label:
                      Text('Claim Round ${state.round} Upgrade (Pick 1 of 3)'),
                ),
              ),
            ),
          ],
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
                        onTap: () => onPlay(index, card),
                        onLongPress: () => showCardInfo(context, card: card),
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

  void _showDraftPicker(BuildContext context) {
    final options = rewardDraftOptions(classId: player.classId);
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.card_giftcard, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Round ${state.round} Upgrade',
                        style: Theme.of(bottomSheetContext)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose 1 card to add to your deck. Long-press any card for full details.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                for (final cardId in options) ...[
                  Builder(
                    builder: (tileContext) {
                      final card = duelCards[cardId];
                      if (card == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: scheme.outlineVariant),
                          ),
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: scheme.primaryContainer,
                            child: Text(
                              '${card.cost}',
                              style: TextStyle(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            card.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(card.description),
                          trailing: const Icon(Icons.add_circle_outline),
                          onTap: () {
                            Navigator.of(bottomSheetContext).pop();
                            onRewardDraft(card.id);
                          },
                          onLongPress: () =>
                              showCardInfo(tileContext, card: card),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DuelCardTile extends StatelessWidget {
  const _DuelCardTile({
    required this.card,
    required this.enabled,
    required this.onTap,
    this.onLongPress,
  });

  final DuelCard card;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

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
