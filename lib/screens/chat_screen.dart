import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/chat.dart';
import '../theme/colors.dart';
import '../utils.dart';
import '../widgets/attachments.dart';
import '../widgets/common.dart';
import 'call_screen.dart';
import 'media_screen.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;
  const ChatScreen({super.key, required this.chat});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ctrl = TextEditingController();
  final scroll = ScrollController();
  List<Msg> get msgs => widget.chat.messages;
  bool get group => widget.chat.group;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    store.addListener(_onStore);
    store.openChat(widget.chat);
  }

  void _onStore() {
    if (!mounted) return;
    setState(() {});
    if (msgs.length != _count) {
      _count = msgs.length;
      _toBottom();
    }
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    store.closeChat(widget.chat);
    _recTimer?.cancel();
    _rec.dispose();
    ctrl.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (scroll.hasClients) {
        scroll.animateTo(scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  final _rec = AudioRecorder();
  bool _recording = false;
  int _recSec = 0;
  Timer? _recTimer;
  final Stopwatch _recWatch = Stopwatch();

  Future<void> _startRec() async {
    try {
      if (!await _rec.hasPermission()) {
        if (mounted) snack(context, 'Microphone permission is needed');
        return;
      }
      final path = kIsWeb
          ? ''
          : '${(await getTemporaryDirectory()).path}/v_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
          RecordConfig(
              encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc),
          path: path);
      _recSec = 0;
      _recWatch
        ..reset()
        ..start();
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recSec = _recWatch.elapsed.inSeconds);
      });
      setState(() => _recording = true);
    } catch (_) {
      if (mounted) snack(context, 'Could not start recording');
    }
  }

  Future<void> _stopRec({required bool send}) async {
    _recTimer?.cancel();
    _recTimer = null;
    _recWatch.stop();
    final elapsed = _recWatch.elapsed;
    final secs = elapsed.inMilliseconds == 0
        ? 1
        : (elapsed.inMilliseconds + 999) ~/ 1000;
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {
      if (mounted) snack(context, 'Could not finish the voice recording');
      return;
    } finally {
      _recWatch.reset();
      if (mounted) setState(() => _recording = false);
    }
    if (!send || path == null) return;
    try {
      final bytes = await XFile(path).readAsBytes();
      if (bytes.isEmpty) throw StateError('The voice recording is empty');
      await store.sendFile(
          widget.chat, 'voice', bytes, kIsWeb ? 'voice.webm' : 'voice.m4a',
          body: '$secs');
    } catch (_) {
      if (mounted) snack(context, 'Could not send the voice message');
    }
  }

  Widget _recBar() => SafeArea(
        top: false,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
              onPressed: () => _stopRec(send: false),
            ),
            const Icon(Icons.fiber_manual_record,
                color: Color(0xFFEF4444), size: 14),
            const SizedBox(width: 8),
            Text(
                '${(_recSec ~/ 60).toString().padLeft(2, '0')}:${(_recSec % 60).toString().padLeft(2, '0')}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            GestureDetector(
              onTap: () => _stopRec(send: true),
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                    color: kPrimary, shape: BoxShape.circle),
                child: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      );

  void _attach() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.image_outlined, color: kPrimary),
            title: const Text('Photo'),
            onTap: () {
              Navigator.pop(ctx);
              _pick('image');
            },
          ),
          ListTile(
            leading:
                const Icon(Icons.insert_drive_file_outlined, color: kPrimary),
            title: const Text('File'),
            onTap: () {
              Navigator.pop(ctx);
              _pick('file');
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _pick(String type) async {
    try {
      final r = await FilePicker.platform.pickFiles(
          type: type == 'image' ? FileType.image : FileType.any,
          withData: true);
      if (r == null || r.files.isEmpty) return;
      final f = r.files.first;
      final bytes = f.bytes ?? await XFile(f.path!).readAsBytes();
      if (bytes.length > 25 * 1024 * 1024) {
        if (mounted) snack(context, 'File too large (25 MB maximum)');
        return;
      }
      await store.sendFile(widget.chat, type, bytes, f.name);
    } catch (_) {
      if (mounted) snack(context, 'Could not send the file');
    }
  }

  Widget _content(Msg m, Color fg) {
    if (m.type == 'image' && m.url != null) {
      final u = store.url(m.url!);
      return GestureDetector(
        onTap: () => go(context, ImageViewer(url: u)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(u,
              width: 220,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => const SizedBox(
                  width: 220,
                  height: 80,
                  child: Center(child: Icon(Icons.broken_image_outlined)))),
        ),
      );
    }
    if (m.type == 'voice' && m.url != null) {
      return VoiceBubble(
          url: store.url(m.url!),
          seconds: int.tryParse(m.text) ?? 0,
          color: fg);
    }
    if (m.type == 'file' && m.url != null) {
      return FileRow(
          name: m.fileName ?? 'File', url: store.url(m.url!), color: fg);
    }
    return Text(m.text, style: TextStyle(color: fg, fontSize: 14));
  }

  void send() {
    final t = ctrl.text.trim();
    if (t.isEmpty) return;
    if (!store.send(widget.chat, t)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not connected to the server')));
      return;
    }
    ctrl.clear();
    store.typing(widget.chat, false);
    setState(() {});
  }

  void _emoji() {
    const list = [
      '😀',
      '😂',
      '😍',
      '😊',
      '😉',
      '😎',
      '🥰',
      '😢',
      '😡',
      '👍',
      '🙏',
      '👏',
      '🎉',
      '❤️',
      '🔥',
      '✨',
      '🤔',
      '😴',
      '🙌',
      '💪'
    ];
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(spacing: 14, runSpacing: 14, children: [
          for (final e in list)
            GestureDetector(
              onTap: () {
                ctrl.text += e;
                setState(() {});
                Navigator.pop(context);
              },
              child: Text(e, style: const TextStyle(fontSize: 28)),
            ),
        ]),
      ),
    );
  }

  Widget _bubble(Msg m) {
    final sentPurple = m.mine && !group;
    final color =
        m.mine ? (group ? const Color(0xFFD9F7CF) : kPrimary) : Colors.white;
    final fg = sentPurple ? Colors.white : kText;
    final sub = sentPurple ? Colors.white70 : kGrey;
    return GestureDetector(
      onLongPress: () => _messageActions(m),
      child: Align(
        alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!m.mine)
                Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 5),
                    child: Avatar(
                      m.sender!,
                      size: 28,
                      imageUrl: store.avatarFor(m.senderId, m.senderAvatarUrl),
                    )),
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * .68),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: .05),
                          blurRadius: 6)
                    ],
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!m.mine && group)
                          Text(m.sender!,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: kPrimary,
                                  fontSize: 12)),
                        _content(m, fg),
                        const SizedBox(height: 4),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(m.time,
                              style: TextStyle(fontSize: 10, color: sub)),
                          if (m.mine) ...[
                            const SizedBox(width: 4),
                            Icon(
                                m.id <= widget.chat.otherLastRead
                                    ? Icons.done_all
                                    : Icons.done,
                                size: 14,
                                color: sentPurple
                                    ? (m.id <= widget.chat.otherLastRead
                                        ? Colors.white
                                        : Colors.white54)
                                    : kPrimary),
                          ],
                        ]),
                      ]),
                ),
              ),
            ]),
      ),
    );
  }

  Future<void> _messageActions(Msg message) async {
    final mode = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
            title: const Text('Delete for me'),
            onTap: () => Navigator.pop(ctx, false),
          ),
          if (message.mine)
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined,
                  color: Color(0xFFEF4444)),
              title: const Text('Delete for everyone'),
              onTap: () => Navigator.pop(ctx, true),
            ),
        ]),
      ),
    );
    if (mode == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(mode ? 'Delete for everyone?' : 'Delete for me?'),
        content: Text(mode
            ? 'This message and its attachment will be removed for all participants.'
            : 'This message will be hidden only in your account.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await store.deleteMessage(widget.chat, message, forEveryone: mode);
    } catch (error) {
      if (mounted) snack(context, 'Could not delete the message: $error');
    }
  }

  Widget _inputBar() => _recording
      ? _recBar()
      : SafeArea(
          top: false,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              GestureDetector(
                  onTap: _attach,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration:
                        const BoxDecoration(color: kBg, shape: BoxShape.circle),
                    child: const Icon(Icons.add, color: kPrimary),
                  )),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  onChanged: (v) {
                    setState(() {});
                    store.typing(widget.chat, v.trim().isNotEmpty);
                  },
                  onSubmitted: (_) => send(),
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    filled: true,
                    fillColor: kBg,
                    suffixIcon: IconButton(
                        icon: const Icon(Icons.emoji_emotions_outlined,
                            color: kGrey),
                        onPressed: _emoji),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: ctrl.text.trim().isEmpty ? _startRec : send,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                      color: kPrimary, shape: BoxShape.circle),
                  child: Icon(ctrl.text.trim().isEmpty ? Icons.mic : Icons.send,
                      color: Colors.white, size: 20),
                ),
              ),
            ]),
          ),
        );

  @override
  Widget build(BuildContext context) {
    void call(bool video) {
      final id = widget.chat.otherUserId;
      if (id != null) startCall(context, id, widget.chat.name, video);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F5FD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () => go(context, MediaScreen(chat: widget.chat)),
          child: Row(children: [
            Avatar(
              widget.chat.name,
              size: 38,
              imageUrl: store.avatarFor(widget.chat.otherUserId, widget.chat.avatarUrl),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.chat.name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              Text(
                  widget.chat.typing
                      ? 'typing...'
                      : (group
                          ? 'Group chat'
                          : (widget.chat.online ? 'Online' : 'Offline')),
                  style: TextStyle(
                      fontSize: 12,
                      color: !group && widget.chat.online ? kGreen : kGrey)),
            ]),
          ]),
        ),
        actions: [
          if (!group)
            IconButton(
                icon: const Icon(Icons.call_outlined),
                onPressed: () => call(false)),
          IconButton(
              icon: const Icon(Icons.videocam_outlined),
              onPressed: () => call(true)),
          if (group) const Icon(Icons.more_vert),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              children: [
                if (msgs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 140),
                    child: Center(
                        child: Text('No messages yet. Say hi! 👋',
                            style: TextStyle(color: kGrey))),
                  ),
                if (msgs.isNotEmpty)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Text('Today',
                          style: TextStyle(fontSize: 12, color: kGrey)),
                    ),
                  ),
                for (final m in msgs) _bubble(m),
              ]),
        ),
        _inputBar(),
      ]),
    );
  }
}
