import 'dart:io';

import 'dart:ui' show PointMode;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/message.dart';
import '../models/reaction.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/wallpaper_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.uid,
    required this.room,
    required this.title,
    this.names = const <String, String>{},
    this.showSenderNames = false,
  });

  final String uid;
  final ChatRoom room;
  final String title;

  /// uid -> display name, used to label bubbles written by other people.
  final Map<String, String> names;

  /// The family room has many authors, so each bubble names its writer.
  final bool showSenderNames;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chat = ChatService();
  final TextEditingController _input = TextEditingController();
  String? _wallpaperPath;
  Message? _replyTo;

  @override
  void initState() {
    super.initState();
    _loadWallpaper();
    NotificationService.instance.setCurrentRoom(widget.room.id);
  }

  Future<void> _loadWallpaper() async {
    final path = await WallpaperService.loadPath();
    if (mounted) setState(() => _wallpaperPath = path);
  }

  @override
  void dispose() {
    NotificationService.instance.setCurrentRoom(null);
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    final reply = _replyTo;
    _input.clear();
    setState(() => _replyTo = null);
    try {
      await _chat.send(
        room: widget.room,
        senderId: widget.uid,
        text: text,
        replyTo: reply?.id ?? '',
        replyToText: reply?.text ?? '',
      );
    } catch (e) {
      if (!mounted) return;
      _input.text = text;
      setState(() => _replyTo = reply);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not send: $e')));
    }
  }

  void _startReply(Message message) {
    if (mounted) setState(() => _replyTo = message);
  }

  void _cancelReply() {
    if (mounted) setState(() => _replyTo = null);
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need your password to sign back in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
      // A chat screen may sit on top of the home screen. The root route
      // swaps to the login screen on sign-out, but pushed routes stay in the
      // stack and would cover it, so pop everything above the root.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Low-contrast pixel dither, behind a wallpaper if one is set.
            Positioned.fill(
              child: RepaintBoundary(
                child: _DitherBackground(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.07),
                ),
              ),
            ),
            if (_wallpaperPath != null) ...[
              Positioned.fill(
                child: RepaintBoundary(
                  child: Image.file(
                    File(_wallpaperPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.45),
                ),
              ),
            ],
            Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<Message>>(
                    stream: _chat.watchMessages(widget.room),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Could not load messages.\n\n'
                              '${snapshot.error}\n\n'
                              'Check that your Firestore security rules are '
                              'published.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      final messages = snapshot.data ?? const <Message>[];
                      if (messages.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No messages yet.\nSay hello!',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      return _MessageList(
                        messages: messages,
                        myUid: widget.uid,
                        room: widget.room,
                        chat: _chat,
                        onReply: _startReply,
                      );
                    },
                  ),
                ),
                _Composer(
                  controller: _input,
                  onSend: _send,
                  replyTo: _replyTo,
                  onCancelReply: _cancelReply,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageList extends StatefulWidget {
  const _MessageList({
    required this.messages,
    required this.myUid,
    required this.room,
    required this.chat,
    required this.onReply,
  });

  final List<Message> messages;
  final String myUid;
  final ChatRoom room;
  final ChatService chat;
  final ValueChanged<Message> onReply;

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(_MessageList old) {
    super.didUpdateWidget(old);
    if (widget.messages.length > old.messages.length) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    DateTime? lastDay;

    for (final m in widget.messages) {
      final day = DateUtils.dateOnly(m.sentAt);
      if (lastDay == null || day != lastDay) {
        items.add(_DaySeparator(date: day));
        lastDay = day;
      }
      items.add(_Bubble(
        message: m,
        isMine: m.senderId == widget.myUid,
        room: widget.room,
        myUid: widget.myUid,
        chat: widget.chat,
        onReply: widget.onReply,
      ));
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, i) => items[i],
    );
  }
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final day = DateUtils.dateOnly(date);
    final label = day == today
        ? 'Today'
        : day == today.subtract(const Duration(days: 1))
            ? 'Yesterday'
            : DateFormat('d MMMM').format(date);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

class _Bubble extends StatefulWidget {
  const _Bubble({
    required this.message,
    required this.isMine,
    required this.room,
    required this.myUid,
    required this.chat,
    required this.onReply,
  });

  static const reactionEmojis = ['❤️', '👍', '😂', '🔥', '😮', '🥺'];

  final Message message;
  final bool isMine;
  final ChatRoom room;
  final String myUid;
  final ChatService chat;
  final ValueChanged<Message> onReply;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  static const String _replyAction = '__reply__';

  /// How far the bubble has slid to the right while preparing a reply.
  double _slide = 0;

  Future<void> _showReactPicker() async {
    final room = widget.room;
    final id = widget.message.id;
    String? current;
    try {
      current = await widget.chat.currentReaction(room, id, widget.myUid);
    } catch (_) {}

    if (!mounted) return;

    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (final e in _Bubble.reactionEmojis)
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx, e),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: e == current
                              ? Theme.of(ctx).colorScheme.primaryContainer
                              : null,
                          shape: BoxShape.circle,
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              ListTile(
                dense: true,
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () => Navigator.pop(ctx, _replyAction),
              ),
            ],
          ),
        ),
      ),
    );

    if (picked == _replyAction) {
      widget.onReply(widget.message);
      return;
    }

    if (picked == null || !mounted) return;
    try {
      if (picked == current) {
        await widget.chat
            .unreact(room: room, messageId: id, userId: widget.myUid);
      } else if (picked.isNotEmpty) {
        await widget.chat.react(
          room: room,
          messageId: id,
          userId: widget.myUid,
          emoji: picked,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not react: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = widget.isMine;
    final bubbleColor =
        mine ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = mine ? (Theme.of(context).brightness==Brightness.dark?Colors.white:scheme.onPrimary) : scheme.onSurface;
    final mutedFg =
        mine ? (Theme.of(context).brightness==Brightness.dark?Colors.white70:scheme.onPrimary.withValues(alpha: 0.8)) : scheme.onSurfaceVariant;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: RepaintBoundary(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                onLongPress: _showReactPicker,
                onHorizontalDragUpdate: (details) {
                  final next = (_slide + details.delta.dx).clamp(0.0, 90.0);
                  if (next != _slide) setState(() => _slide = next);
                },
                onHorizontalDragEnd: (details) {
                  final wasSlid = _slide;
                  if (mounted) setState(() => _slide = 0);
                  final shouldReply =
                      wasSlid >= 70 || (details.primaryVelocity ?? 0) > 300;
                  if (shouldReply && wasSlid >= 30) {
                    widget.onReply(widget.message);
                  }
                },
                onHorizontalDragCancel: () {
                  if (mounted) setState(() => _slide = 0);
                },
                child: Transform.translate(
                  offset: Offset(_slide, 0),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: CustomPaint(
                      painter: _BubblePainter(color: bubbleColor, mine: mine),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.message.replyToText.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 5),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: fg.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(8),
                            border: Border(
                              left: BorderSide(
                                color: fg.withValues(alpha: 0.45),
                                width: 3,
                              ),
                            ),
                          ),
                          child: Text(
                            _clamp(widget.message.replyToText),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: mutedFg,
                              fontSize: 13,
                              height: 1.25,
                            ),
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.message.text,
                          style: TextStyle(color: fg, fontSize: 16),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.message.isPending) ...[
                            Icon(Icons.schedule, size: 11, color: mutedFg),
                            const SizedBox(width: 3),
                          ],
                          Text(
                            DateFormat.Hm().format(widget.message.sentAt),
                            style: TextStyle(color: mutedFg, fontSize: 10),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: StreamBuilder<List<Reaction>>(
                          stream: widget.chat
                              .watchReactions(widget.room, widget.message.id),
                          builder: (context, snapshot) => _ReactionChips(
                            reactions: snapshot.data ?? const <Reaction>[],
                            myUid: widget.myUid,
                          ),
                        ),
                      ),
                      ],
                    ),
                  ),
                ),
              ),
              ),
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A shade lighter of a bubble colour, used for the glossy iPhone-style top
/// of the bubble gradient.
Color _lighten(Color color) => Color.lerp(color, Colors.white, 0.28)!;

/// A shade darker of a bubble colour, used for the bottom of the bubble
/// gradient and its 1px outline.
Color _darken(Color color) => Color.lerp(color, Colors.black, 0.18)!;

/// Shortens quoted text so reply previews stay a couple of lines max.
String _clamp(String text, [int max = 120]) =>
    text.length <= max ? text : '${text.substring(0, max)}…';

/// Paints an iPhone-style bubble: a glossy pill with a small tail on the
/// speaker's side, a 1px outline and a soft drop shadow.
class _BubblePainter extends CustomPainter {
  _BubblePainter({required this.color, required this.mine});

  final Color color;
  final bool mine;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = const Radius.circular(22);
    final tailRadius = const Radius.circular(6);
    final rrect = RRect.fromRectAndCorners(
      rect,
      topLeft: radius,
      topRight: radius,
      bottomLeft: mine ? radius : tailRadius,
      bottomRight: mine ? tailRadius : radius,
    );
    final path = Path()..addRRect(rrect);

    // A small wedge breaking out of the bottom corner on the speaker's side.
    final tail = Path();
    if (mine) {
      final cx = size.width - 14;
      tail
        ..moveTo(cx - 10, size.height)
        ..lineTo(cx - 2, size.height - 12)
        ..lineTo(cx + 7, size.height + 6)
        ..close();
    } else {
      final cx = 14;
      tail
        ..moveTo(cx + 10, size.height)
        ..lineTo(cx + 2, size.height - 12)
        ..lineTo(cx - 7, size.height + 6)
        ..close();
    }
    final shape = Path.combine(PathOperation.union, path, tail);

    // Soft drop shadow, offset slightly downward.
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.save();
    canvas.translate(0, 2);
    canvas.drawPath(shape, shadowPaint);
    canvas.restore();

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_lighten(color), color, _darken(color)],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawPath(shape, fill);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _darken(color);
    canvas.drawPath(shape, stroke);
  }

  @override
  bool shouldRepaint(_BubblePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.mine != mine;
}

class _ReactionChips extends StatelessWidget {
  const _ReactionChips({required this.reactions, required this.myUid});

  final List<Reaction> reactions;
  final String myUid;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final byEmoji = <String, int>{};
    var mineIncluded = false;
    for (final r in reactions) {
      byEmoji[r.emoji] = (byEmoji[r.emoji] ?? 0) + 1;
      if (r.uid == myUid) mineIncluded = true;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in byEmoji.entries)
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: mineIncluded ? scheme.primary : scheme.surface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                e.value > 1 ? '${e.key} ${e.value}' : e.key,
                style: TextStyle(
                  fontSize: 11,
                  color: mineIncluded ? (Theme.of(context).brightness==Brightness.dark?Colors.white:scheme.onPrimary) : scheme.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A sparse, low-contrast grid of dots that gives the chat a retro dithered
/// texture without distracting from the bubbles.
class _DitherBackground extends StatelessWidget {
  const _DitherBackground({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DitherPainter(color),
        size: Size.infinite,
      );
}

class _DitherPainter extends CustomPainter {
  _DitherPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square;
    const cell = 4.0;
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    final points = <Offset>[];
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        if ((row + col).isEven) continue;
        points.add(Offset(col * cell + 1, row * cell + 1));
      }
    }
    canvas.drawPoints(PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(_DitherPainter oldDelegate) => oldDelegate.color != color;
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onCancelReply,
    this.replyTo,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onCancelReply;
  final Message? replyTo;

  @override
  Widget build(BuildContext context) {
    final reply = replyTo;
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (reply != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(12, 4, 2, 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.reply, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _clamp(reply.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onCancelReply,
                  ),
                ],
              ),
            ),
          Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Message',
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: onSend,
            icon: const Icon(Icons.send),
          ),
          ],
        ),
        ],
      ),
    );
  }
}
