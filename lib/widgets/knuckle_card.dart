import 'package:flutter/material.dart';

import '../screens/knuckle_screen.dart';
import '../services/chat_service.dart';
import '../services/knuckle_engine.dart';
import '../services/knuckle_service.dart';

class KnuckleCardBubble extends StatefulWidget {
  const KnuckleCardBubble({
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
  State<KnuckleCardBubble> createState() => _KnuckleCardBubbleState();
}

class _KnuckleCardBubbleState extends State<KnuckleCardBubble> {
  final KnuckleService _service = KnuckleService();
  Stream<KnuckleState?>? _stream;

  @override
  void initState() {
    super.initState();
    _stream = _service.watchKnuckle(widget.room, widget.gameId);
  }

  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => KnuckleScreen(
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return StreamBuilder<KnuckleState?>(
      stream: _stream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final myScore = state?.scoreFor(widget.myUid) ?? 0;
        final theirScore = state == null
            ? 0
            : state.scoreFor(state.otherUid(widget.myUid));

        final String status;
        final String badge;
        if (state == null) {
          status = 'Loading the board...';
          badge = 'Open';
        } else if (state.isFinished) {
          badge = 'Final';
          if (state.winner == widget.myUid) {
            status = 'You won $myScore - $theirScore';
          } else if (state.winner == 'draw') {
            status = 'Draw at $myScore - $theirScore';
          } else {
            status = '${widget.opponentName} won $theirScore - $myScore';
          }
        } else if (state.turn == widget.myUid) {
          badge = 'Your turn';
          status = state.pendingRoll == 0
              ? 'Roll the bones'
              : 'Place your ${state.pendingRoll} in a column';
        } else {
          badge = 'Waiting';
          status = state.pendingRoll == 0
              ? 'Waiting for ${widget.opponentName}'
              : '${widget.opponentName} is placing';
        }

        return GestureDetector(
          onTap: _open,
          child: Container(
            width: 270,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primaryContainer,
                  scheme.surfaceContainerHighest,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.casino,
                      size: 18,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Knucklebones',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ScoreLine(
                  name: widget.myName,
                  score: myScore,
                  color: scheme.primary,
                ),
                const SizedBox(height: 6),
                _ScoreLine(
                  name: widget.opponentName,
                  score: theirScore,
                  color: scheme.tertiary,
                ),
                const SizedBox(height: 10),
                Text(
                  status,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  state?.isFinished ?? false
                      ? 'Tap to rematch'
                      : 'Tap to open the board',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ScoreLine extends StatelessWidget {
  const _ScoreLine({
    required this.name,
    required this.score,
    required this.color,
  });

  final String name;
  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          '$score',
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
