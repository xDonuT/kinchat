import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/message.dart';
import '../models/reaction.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/wallpaper_service.dart';
import '../palette.dart';

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
    _input.clear();
    try {
      await _chat.send(room: widget.room, senderId: widget.uid, text: text);
    } catch (e) {
      if (!mounted) return;
      _input.text = text;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not send: $e')));
    }
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
            if (_wallpaperPath != null) ...[
              Positioned.fill(
                child: Image.file(
                  File(_wallpaperPath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
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
                        names: widget.names,
                        showSenderNames: widget.showSenderNames,
                        room: widget.room,
                        chat: _chat,
                      );
                    },
                  ),
                ),
                _Composer(controller: _input, onSend: _send),
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
    required this.names,
    required this.showSenderNames,
    required this.room,
    required this.chat,
  });

  final List<Message> messages;
  final String myUid;
  final Map<String, String> names;
  final bool showSenderNames;
  final ChatRoom room;
  final ChatService chat;

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

  String _nameFor(String uid) {
    if (uid == widget.myUid) return 'You';
    return widget.names[uid] ?? 'Family member';
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
        senderName: widget.showSenderNames ? _nameFor(m.senderId) : null,
        room: widget.room,
        myUid: widget.myUid,
        chat: widget.chat,
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
    this.senderName,
  });

  static const reactionEmojis = ['❤️', '👍', '😂', '🔥', '😮', '🥺'];

  final Message message;
  final bool isMine;
  final ChatRoom room;
  final String myUid;
  final ChatService chat;
  final String? senderName;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
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
          child: Row(
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
        ),
      ),
    );

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
    final fg = mine ? scheme.onPrimary : scheme.onSurface;
    final mutedFg =
        mine ? scheme.onPrimary.withValues(alpha: 0.8) : scheme.onSurfaceVariant;

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
            if (!mine) ...[
              _Avatar(name: widget.senderName, uid: widget.message.senderId),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: GestureDetector(
                onLongPress: _showReactPicker,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.senderName != null) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            widget.senderName!,
                            style: TextStyle(
                              color: mutedFg,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
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
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.uid, this.name});

  final String uid;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final color = colorForUid(uid);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: CircleAvatar(
        radius: 14,
        backgroundColor: color,
        child: Text(
          initialFor(name ?? ''),
          style: TextStyle(
            color: onColorFor(color),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
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
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                e.value > 1 ? '${e.key} ${e.value}' : e.key,
                style: TextStyle(
                  fontSize: 11,
                  color: mineIncluded ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
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
    );
  }
}
