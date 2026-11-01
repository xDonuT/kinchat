import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../services/knuckle_engine.dart';
import '../services/knuckle_service.dart';
import '../services/knuckle_sfx.dart';

class KnuckleScreen extends StatefulWidget {
  const KnuckleScreen({
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
  State<KnuckleScreen> createState() => _KnuckleScreenState();
}

class _KnuckleScreenState extends State<KnuckleScreen> {
  final KnuckleService _service = KnuckleService();
  final Random _random = Random();

  StreamSubscription<KnuckleState?>? _subscription;
  KnuckleState? _state;
  Object? _error;
  bool _busy = false;
  bool _rolling = false;
  int _displayRoll = 1;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _subscription?.cancel();
    _subscription = _service
        .watchKnuckle(widget.room, widget.gameId)
        .listen(
          (state) {
            if (!mounted) return;
            setState(() {
              _state = state;
              _error = null;
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() => _error = error);
          },
        );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _roll() async {
    final state = _state;
    if (_busy || _rolling || state == null) return;
    if (state.isFinished ||
        state.turn != widget.myUid ||
        state.pendingRoll != 0) {
      return;
    }

    setState(() => _busy = true);
    try {
      final next = await _service.roll(
        room: widget.room,
        gameId: widget.gameId,
        uid: widget.myUid,
      );
      if (!mounted) return;
      setState(() {
        _state = next;
        _busy = false;
        _rolling = true;
        _displayRoll = 1 + _random.nextInt(6);
      });

      for (var tick = 0; tick < 7; tick++) {
        await Future<void>.delayed(const Duration(milliseconds: 55));
        if (!mounted) return;
        setState(() => _displayRoll = 1 + _random.nextInt(6));
      }

      if (!mounted) return;
      setState(() {
        _displayRoll = next.pendingRoll;
        _rolling = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError(error);
    }
  }

  Future<void> _place(int column) async {
    final state = _state;
    if (_busy || _rolling || state == null) return;
    if (state.isFinished ||
        state.turn != widget.myUid ||
        state.pendingRoll == 0) {
      return;
    }
    if (column < 0 || column >= KnuckleState.columnCount) return;
    if (state.columnsFor(widget.myUid)[column].length >=
        KnuckleState.maxPerColumn) {
      return;
    }

    setState(() => _busy = true);
    try {
      final next = await _service.place(
        room: widget.room,
        gameId: widget.gameId,
        uid: widget.myUid,
        column: column,
      );
      if (!mounted) return;
      setState(() {
        _state = next;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError(error);
    }
  }

  Future<void> _rematch() async {
    final state = _state;
    if (_busy || _rolling || state == null || !state.isFinished) return;

    setState(() => _busy = true);
    try {
      final next = await _service.rematch(
        room: widget.room,
        gameId: widget.gameId,
        uid: widget.myUid,
      );
      if (!mounted) return;
      setState(() {
        _state = next;
        _busy = false;
        _displayRoll = 1;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError(error);
    }
  }

  void _showError(Object error) {
    final message = error is KnuckleException
        ? error.message
        : 'Something went wrong. Try again.';
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: SingleChildScrollView(
          child: SelectableText('$message\n\n$error'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  AppBar _appBar() {
    return AppBar(
      title: const Text('Knucklebones'),
      actions: [
        IconButton(
          onPressed: _showRules,
          icon: const Icon(Icons.help_outline_rounded),
          tooltip: 'How to play',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = _state;
    final errorText = _error is KnuckleException
        ? (_error as KnuckleException).message
        : 'Could not load this game.';

    if (_error != null && state == null) {
      return Scaffold(
        appBar: _appBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 48,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  errorText,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                if (_error is! KnuckleException) ...[
                  const SizedBox(height: 8),
                  Text(
                    '$_error',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() => _error = null);
                    _listen();
                  },
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (state == null) {
      return Scaffold(
        appBar: _appBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final otherUid = state.otherUid(widget.myUid);
    final myColumns = state.columnsFor(widget.myUid);
    final theirColumns = state.columnsFor(otherUid);
    final myScore = state.scoreFor(widget.myUid);
    final theirScore = state.scoreFor(otherUid);
    final myTurn = !state.isFinished && state.turn == widget.myUid;
    final theirTurn = !state.isFinished && state.turn == otherUid;
    final pending = state.pendingRoll;
    final displayedRoll = _rolling
        ? _displayRoll
        : (pending == 0 ? null : pending);
    final canPlace = myTurn && pending != 0 && !_busy && !_rolling;
    final canRoll = myTurn && pending == 0 && !_busy && !_rolling;
    final finished = state.isFinished;

    final String statusText;
    final Color statusColor;
    final IconData statusIcon;
    if (finished) {
      if (state.winner == widget.myUid) {
        statusText = 'You win $myScore - $theirScore';
        statusColor = scheme.primary;
        statusIcon = Icons.emoji_events_rounded;
      } else if (state.winner == 'draw') {
        statusText = 'Draw at $myScore - $theirScore';
        statusColor = scheme.onSurfaceVariant;
        statusIcon = Icons.handshake_rounded;
      } else {
        statusText = '${widget.opponentName} wins $theirScore - $myScore';
        statusColor = scheme.error;
        statusIcon = Icons.sentiment_dissatisfied_rounded;
      }
    } else if (_rolling) {
      statusText = 'Rolling...';
      statusColor = scheme.primary;
      statusIcon = Icons.casino;
    } else if (myTurn) {
      statusText = pending != 0
          ? 'Place your $pending in a column'
          : 'Your turn - roll the bones';
      statusColor = scheme.primary;
      statusIcon = Icons.casino;
    } else if (theirTurn && pending != 0) {
      statusText = 'Waiting for ${widget.opponentName} to place';
      statusColor = scheme.onSurface;
      statusIcon = Icons.hourglass_bottom_rounded;
    } else {
      statusText = 'Waiting for ${widget.opponentName}...';
      statusColor = scheme.onSurface;
      statusIcon = Icons.hourglass_empty_rounded;
    }

    final dieBackground = state.turn == widget.myUid || _rolling
        ? scheme.primaryContainer
        : scheme.tertiaryContainer;
    final diePip = state.turn == widget.myUid || _rolling
        ? scheme.onPrimaryContainer
        : scheme.onTertiaryContainer;

    return Scaffold(
      appBar: _appBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            children: [
              Expanded(
                child: _PlayerPanel(
                  name: widget.opponentName,
                  columns: theirColumns,
                  score: theirScore,
                  accent: scheme.tertiary,
                  dieBackground: scheme.tertiaryContainer,
                  pipColor: scheme.onTertiaryContainer,
                  active: theirTurn,
                  canPlace: (_) => false,
                  ghostValue: null,
                  onPlace: _place,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 50,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: displayedRoll != null
                                ? _Die(
                                    value: displayedRoll,
                                    background: dieBackground,
                                    pipColor: diePip,
                                  )
                                : _ResultIcon(
                                    icon: statusIcon,
                                    color: statusColor,
                                  ),
                          ),
                          const SizedBox(width: 14),
                          Flexible(
                            child: Text(
                              statusText,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: finished
                          ? (_busy ? null : _rematch)
                          : (canRoll ? _roll : null),
                      icon: Icon(
                        finished ? Icons.replay_rounded : Icons.casino,
                      ),
                      label: Text(finished ? 'Rematch' : 'Roll'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(180, 46),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _PlayerPanel(
                  name: widget.myName,
                  columns: myColumns,
                  score: myScore,
                  accent: scheme.primary,
                  dieBackground: scheme.primaryContainer,
                  pipColor: scheme.onPrimaryContainer,
                  active: myTurn,
                  canPlace: (column) =>
                      canPlace &&
                      state.columnsFor(widget.myUid)[column].length <
                          KnuckleState.maxPerColumn,
                  ghostValue: canPlace ? pending : null,
                  onPlace: _place,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRules() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How to play'),
        content: SingleChildScrollView(
          child: Text(
            'Take turns rolling a die and placing it in one of your three '
            'columns. A filled column cannot take more dice.\n\n'
            'Matching dice multiply: a column with 4-4-1 scores '
            '(4 + 4) x 2 + 1 = 17.\n\n'
            'Placing a value knocks out every matching die in the same '
            'column of your rival\'s board.\n\n'
            'The game ends as soon as either board is full. '
            'Highest total score wins.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel({
    required this.name,
    required this.columns,
    required this.score,
    required this.accent,
    required this.dieBackground,
    required this.pipColor,
    required this.active,
    required this.canPlace,
    required this.ghostValue,
    required this.onPlace,
  });

  final String name;
  final List<List<int>> columns;
  final int score;
  final Color accent;
  final Color dieBackground;
  final Color pipColor;
  final bool active;
  final bool Function(int column) canPlace;
  final int? ghostValue;
  final ValueChanged<int> onPlace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final breakdown = columns
        .map((column) => KnuckleState.columnScore(column))
        .join(' + ');
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

    return Column(
      children: [
        Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: active ? 0.28 : 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: active
                      ? accent
                      : scheme.outlineVariant.withValues(alpha: 0.6),
                  width: active ? 2 : 1,
                ),
              ),
              child: Center(
                child: Text(
                  initial,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: active ? accent : scheme.onSurface,
                    ),
                  ),
                  Text(
                    'Columns  $breakdown',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '$score',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: _Board(
                columns: columns,
                accent: accent,
                dieBackground: dieBackground,
                pipColor: pipColor,
                canPlace: canPlace,
                ghostValue: ghostValue,
                onPlace: onPlace,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({
    required this.columns,
    required this.accent,
    required this.dieBackground,
    required this.pipColor,
    required this.canPlace,
    required this.ghostValue,
    required this.onPlace,
  });

  final List<List<int>> columns;
  final Color accent;
  final Color dieBackground;
  final Color pipColor;
  final bool Function(int column) canPlace;
  final int? ghostValue;
  final ValueChanged<int> onPlace;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          for (var column = 0; column < KnuckleState.columnCount; column++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _Column(
                  dice: columns[column],
                  accent: accent,
                  dieBackground: dieBackground,
                  pipColor: pipColor,
                  placeable: canPlace(column),
                  ghostValue: ghostValue,
                  onTap: () => onPlace(column),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.dice,
    required this.accent,
    required this.dieBackground,
    required this.pipColor,
    required this.placeable,
    required this.ghostValue,
    required this.onTap,
  });

  final List<int> dice;
  final Color accent;
  final Color dieBackground;
  final Color pipColor;
  final bool placeable;
  final int? ghostValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filled = dice.length;
    final ghostSlot = placeable && ghostValue != null
        ? KnuckleState.maxPerColumn - 1 - filled
        : -1;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: placeable ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: placeable
              ? accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: placeable
                ? accent
                : scheme.outlineVariant.withValues(alpha: 0.6),
            width: placeable ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            for (var slot = 0; slot < KnuckleState.maxPerColumn; slot++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: _slot(slot, filled, ghostSlot),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _slot(int slot, int filled, int ghostSlot) {
    final occupiedFrom = KnuckleState.maxPerColumn - filled;

    if (slot >= occupiedFrom) {
      final value = dice[filled - KnuckleState.maxPerColumn + slot];
      return _Die(value: value, background: dieBackground, pipColor: pipColor);
    }

    if (slot == ghostSlot) {
      return _Die(
        value: ghostValue!,
        background: dieBackground,
        pipColor: pipColor,
        ghost: true,
      );
    }

    return Center(
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _ResultIcon extends StatelessWidget {
  const _ResultIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Icon(icon, color: scheme.onSurfaceVariant, size: 24),
    );
  }
}

class _Die extends StatelessWidget {
  const _Die({
    required this.value,
    required this.background,
    required this.pipColor,
    this.ghost = false,
  });

  final int value;
  final Color background;
  final Color pipColor;
  final bool ghost;

  static const Map<int, List<int>> _pipCells = {
    1: [4],
    2: [0, 8],
    3: [0, 4, 8],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };

  @override
  Widget build(BuildContext context) {
    final cells = _pipCells[value] ?? const <int>[];

    return Opacity(
      opacity: ghost ? 0.32 : 1,
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final raw = constraints.biggest.shortestSide;
              final size = raw.isFinite && raw > 0 ? raw : 40.0;
              final dot = size * 0.16;
              final radius = size * 0.2;

              return Container(
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.12),
                    width: 1.2,
                  ),
                  boxShadow: ghost
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: size * 0.08,
                            offset: Offset(0, size * 0.04),
                          ),
                        ],
                ),
                padding: EdgeInsets.all(size * 0.14),
                child: Column(
                  children: [
                    for (var row = 0; row < 3; row++)
                      Expanded(
                        child: Row(
                          children: [
                            for (var column = 0; column < 3; column++)
                              Expanded(
                                child: Center(
                                  child: cells.contains(row * 3 + column)
                                      ? Container(
                                          width: dot,
                                          height: dot,
                                          decoration: BoxDecoration(
                                            color: pipColor,
                                            shape: BoxShape.circle,
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
