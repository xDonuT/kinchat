import 'dart:async';
import 'dart:io';

import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/message.dart';
import '../models/reaction.dart';
import '../services/chat_service.dart';
import '../services/kuteken_emoji.dart';
import '../services/notification_service.dart';
import '../services/wallpaper_service.dart';
import 'image_viewer_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.uid,
    required this.room,
    required this.title,
    this.names = const <String, String>{},
  });

  final String uid;
  final ChatRoom room;
  final String title;

  /// uid -> display name, used to label bubbles written by other people.
  final Map<String, String> names;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chat = ChatService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _input = TextEditingController();
  String? _wallpaperPath;
  Message? _replyTo;
  Timer? _draftTimer;

  String get _draftKey => 'chat_draft_${widget.uid}_${widget.room.id}';

  @override
  void initState() {
    super.initState();
    _loadWallpaper();
    _input.addListener(_onDraftChanged);
    _restoreDraft();
    NotificationService.instance.setCurrentRoom(widget.room.id);
  }

  Future<void> _restoreDraft() async {
    final draft = (await SharedPreferences.getInstance()).getString(_draftKey);
    if (!mounted || draft == null || draft.isEmpty || _input.text.isNotEmpty) {
      return;
    }
    _input.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }

  void _onDraftChanged() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), () {
      _persistDraft(_input.text);
    });
  }

  Future<void> _persistDraft(String text) async {
    final prefs = await SharedPreferences.getInstance();
    if (text.trim().isEmpty) {
      await prefs.remove(_draftKey);
    } else {
      await prefs.setString(_draftKey, text);
    }
  }

  Future<void> _loadWallpaper() async {
    final path = await WallpaperService.loadPath();
    if (mounted) setState(() => _wallpaperPath = path);
  }

  @override
  void dispose() {
    NotificationService.instance.setCurrentRoom(null);
    _draftTimer?.cancel();
    _input.removeListener(_onDraftChanged);
    unawaited(_persistDraft(_input.text));
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
        replyToText: reply?.preview ?? '',
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

  Future<void> _pickAndSendPhoto() async {
    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
        requestFullMetadata: false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the gallery: $e')),
        );
      }
      return;
    }
    if (picked == null || !mounted) return;

    final Uint8List bytes;
    final int width;
    final int height;
    try {
      bytes = await picked.readAsBytes();
      // Reading only the header avoids decoding the whole photo twice.
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      width = descriptor.width;
      height = descriptor.height;
      descriptor.dispose();
      buffer.dispose();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read that photo: $e')),
        );
      }
      return;
    }
    if (!mounted) return;

    final reply = _replyTo;
    setState(() => _replyTo = null);

    final progress = ValueNotifier<double>(0);
    final dialogClosed = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UploadDialog(progress: progress),
    );

    try {
      await _chat.sendImage(
        room: widget.room,
        senderId: widget.uid,
        bytes: bytes,
        width: width,
        height: height,
        replyTo: reply?.id ?? '',
        replyToText: reply?.preview ?? '',
        onProgress: (value) => progress.value = value,
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() => _replyTo = reply);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not send photo: $e')));
      }
      unawaited(dialogClosed.whenComplete(progress.dispose));
      return;
    }

    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    unawaited(dialogClosed.whenComplete(progress.dispose));
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
                  color: Theme.of(context).colorScheme.primary
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
                  color: Theme.of(context).colorScheme.surface
                      .withValues(alpha: 0.45),
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
                  onPickPhoto: _pickAndSendPhoto,
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
  bool _atBottom = true;
  int _unseen = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom = _scroll.position.pixels < 120;
    if (atBottom == _atBottom) return;
    setState(() {
      _atBottom = atBottom;
      if (atBottom) _unseen = 0;
    });
  }

  @override
  void didUpdateWidget(_MessageList old) {
    super.didUpdateWidget(old);
    final added = widget.messages.length - old.messages.length;
    if (added > 0) {
      // Follow new messages while at the bottom, or when the new message is
      // ours. Reading old messages is not interrupted by someone else.
      final latest = widget.messages.last;
      final mine = latest.senderId == widget.myUid;
      if (mine || _atBottom) {
        _unseen = 0;
        _scrollToBottom();
      } else {
        _unseen += added;
      }
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _jumpToLatest() {
    HapticFeedback.selectionClick();
    if (_unseen != 0) setState(() => _unseen = 0);
    _scrollToBottom();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
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
      items.add(
        _Bubble(
          message: m,
          isMine: m.senderId == widget.myUid,
          room: widget.room,
          myUid: widget.myUid,
          chat: widget.chat,
          onReply: widget.onReply,
        ),
      );
    }

    final showJump = !_atBottom || _unseen > 0;

    // Reversing both the children and the scroll axis keeps the historical
    // order but anchors the viewport to the newest message on first open.
    return Stack(
      children: [
        ListView.builder(
          reverse: true,
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: items.length,
          itemBuilder: (context, i) => items[items.length - 1 - i],
        ),
        Positioned(
          right: 16,
          bottom: 12,
          child: IgnorePointer(
            ignoring: !showJump,
            child: AnimatedScale(
              scale: showJump ? 1 : 0.85,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: showJump ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: FloatingActionButton.small(
                  heroTag: null,
                  tooltip: 'Jump to latest',
                  onPressed: _jumpToLatest,
                  child: Badge.count(
                    count: _unseen,
                    isLabelVisible: _unseen > 0,
                    child: const Icon(Icons.keyboard_arrow_down),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
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

  static const reactionEmojis = ['❤️', '😂', '😡', '🥺', '🤯', '🥳'];

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
  static const String _copyAction = '__copy__';

  /// How far the bubble has slid to the right while preparing a reply.
  double _slide = 0;

  void _openPhoto() {
    final message = widget.message;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImageViewerScreen(
          imageUrl: message.imageUrl,
          heroTag: 'photo-${message.id}',
        ),
      ),
    );
  }

  /// A compact, memory-friendly preview. The image is decoded at roughly the
  /// width it is drawn at, so scrolling never holds a full-resolution bitmap
  /// per bubble; the full photo is only loaded when it is opened.
  Widget _photo() {
    final message = widget.message;
    final ratio = message.imageWidth > 0 && message.imageHeight > 0
        ? message.imageWidth / message.imageHeight
        : 4 / 3;

    return GestureDetector(
      onTap: _openPhoto,
      child: Hero(
        tag: 'photo-${message.id}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240, maxHeight: 300),
            child: AspectRatio(
              aspectRatio: ratio,
              child: Image.network(
                message.imageUrl,
                semanticLabel: 'Photo',
                fit: BoxFit.cover,
                cacheWidth: 720,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  final total = progress.expectedTotalBytes;
                  return SizedBox(
                    width: 240,
                    height: (240 / ratio).clamp(120.0, 300.0),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: total == null
                              ? null
                              : progress.cumulativeBytesLoaded / total,
                        ),
                      ),
                    ),
                  );
                },
                errorBuilder: (_, _, _) => SizedBox(
                  width: 240,
                  height: 160,
                  child: Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

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
                        child: KutekenEmoji(
                          e,
                          size: 28,
                          fallbackStyle: const TextStyle(fontSize: 28),
                        ),
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
              if (!widget.message.isImage && widget.message.text.isNotEmpty)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.copy),
                  title: const Text('Copy'),
                  onTap: () => Navigator.pop(ctx, _copyAction),
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

    if (picked == _copyAction) {
      await Clipboard.setData(ClipboardData(text: widget.message.text));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Copied')));
      }
      return;
    }

    if (picked == null || !mounted) return;
    try {
      if (picked == current) {
        await widget.chat.unreact(
          room: room,
          messageId: id,
          userId: widget.myUid,
        );
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not react: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = widget.isMine;
    final bubbleColor = mine ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = mine
        ? (Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : scheme.onPrimary)
        : scheme.onSurface;
    final mutedFg = mine
        ? (Theme.of(context).brightness == Brightness.dark
              ? Colors.white70
              : scheme.onPrimary.withValues(alpha: 0.8))
        : scheme.onSurfaceVariant;

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
                                  child: KutekanEmojiText(
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
                              if (widget.message.isImage)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: _photo(),
                                )
                              else
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: KutekanEmojiText(
                                    widget.message.text,
                                    style: TextStyle(color: fg, fontSize: 16),
                                  ),
                                ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.message.isPending) ...[
                                    Icon(
                                      Icons.schedule,
                                      size: 11,
                                      color: mutedFg,
                                    ),
                                    const SizedBox(width: 3),
                                  ],
                                  Text(
                                    DateFormat.Hm().format(
                                      widget.message.sentAt,
                                    ),
                                    style: TextStyle(
                                      color: mutedFg,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: StreamBuilder<List<Reaction>>(
                                  stream: widget.chat.watchReactions(
                                    widget.room,
                                    widget.message.id,
                                  ),
                                  builder: (context, snapshot) =>
                                      _ReactionChips(
                                        reactions:
                                            snapshot.data ?? const <Reaction>[],
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KutekenEmoji(
                    e.key,
                    size: 14,
                    fallbackStyle: TextStyle(
                      fontSize: 11,
                      color: mineIncluded
                          ? (Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : scheme.onPrimary)
                          : scheme.onSurface,
                    ),
                  ),
                  if (e.value > 1)
                    Text(
                      ' ${e.value}',
                      style: TextStyle(
                        fontSize: 11,
                        color: mineIncluded
                            ? (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white
                                  : scheme.onPrimary)
                            : scheme.onSurface,
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

/// A sparse, low-contrast grid of dots that gives the chat a retro dithered
/// texture without distracting from the bubbles.
class _DitherBackground extends StatelessWidget {
  const _DitherBackground({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DitherPainter(color), size: Size.infinite);
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
    canvas.drawPoints(ui.PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(_DitherPainter oldDelegate) => oldDelegate.color != color;
}

class _UploadDialog extends StatelessWidget {
  const _UploadDialog({required this.progress});

  final ValueListenable<double> progress;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sending photo'),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: value > 0 ? value : null),
            const SizedBox(height: 10),
            Text(
              value >= 1
                  ? 'Finishing…'
                  : value > 0
                  ? '${(value * 100).round()}%'
                  : 'Starting…',
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onPickPhoto,
    required this.onCancelReply,
    this.replyTo,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onPickPhoto;
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
                    child: KutekanEmojiText(
                      _clamp(reply.preview),
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
              IconButton(
                tooltip: 'Send photo',
                onPressed: onPickPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.newline,
                  cursorColor: const Color(0xFFFF0000),
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
