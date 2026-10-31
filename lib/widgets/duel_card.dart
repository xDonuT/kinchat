import 'package:flutter/material.dart';

import '../models/duel.dart';
import '../screens/duel_screen.dart';
import '../services/chat_service.dart';
import '../services/duel_service.dart';

/// Compact duel card shown in the chat history. It subscribes only to its own
/// duel document, so a move does not rebuild the surrounding message list.
class DuelCardBubble extends StatefulWidget {
  const DuelCardBubble({
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
  State<DuelCardBubble> createState() => _DuelCardBubbleState();
}

class _DuelCardBubbleState extends State<DuelCardBubble> {
  final DuelService _service = DuelService();

  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DuelScreen(
          room: widget.room,
          gameId: widget.gameId,
          myUid: widget.myUid,
          myName: widget.myName,
          opponentName: widget.opponentName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DuelState?>(
      stream: _service.watchDuel(widget.room, widget.gameId),
      builder: (context, snapshot) {
        final scheme = Theme.of(context).colorScheme;
        final state = snapshot.data;
        final available = state != null;
        final status = state == null
            ? 'Duel unavailable.'
            : state.isLobby
            ? (state.player(widget.myUid)?.ready ?? false
                  ? 'Waiting for ${widget.opponentName}'
                  : 'Choose your class')
            : state.isFinished
            ? (state.winner == widget.myUid
                  ? 'You won the duel'
                  : '${widget.opponentName} won the duel')
            : (state.turn == widget.myUid
                  ? 'Your turn'
                  : 'Waiting for ${widget.opponentName}');

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: available ? _open : null,
            child: Container(
              width: 260,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [
                    scheme.primaryContainer,
                    scheme.surfaceContainerHighest,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.sports_esports,
                        size: 20,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Duel',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        state == null
                            ? ''
                            : state.isLobby
                            ? 'Lobby'
                            : 'Round ${state.round}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (state == null)
                    Text(
                      'This duel is no longer available.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    )
                  else ...[
                    _MiniPlayerLine(
                      name: widget.opponentName,
                      player: state.player(state.otherUid(widget.myUid)),
                    ),
                    const SizedBox(height: 6),
                    _MiniPlayerLine(
                      name: widget.myName,
                      player: state.player(widget.myUid),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      status,
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      state.isLobby
                          ? 'Tap to choose your class'
                          : 'Tap to open the board',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniPlayerLine extends StatelessWidget {
  const _MiniPlayerLine({required this.name, required this.player});

  final String name;
  final DuelPlayer? player;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hp = player?.hp ?? 0;
    final maxHp = player?.maxHp ?? 1;
    final ratio = maxHp <= 0 ? 0.0 : (hp / maxHp).clamp(0.0, 1.0);
    final className = duelClasses[player?.classId]?.name ?? '';
    final label = className.isEmpty ? name : '$name · $className';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text('$hp/$maxHp', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 5,
            backgroundColor: scheme.surface,
            color: ratio > 0.25 ? scheme.primary : scheme.error,
          ),
        ),
      ],
    );
  }
}
