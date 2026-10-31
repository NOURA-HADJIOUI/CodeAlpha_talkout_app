import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../theme/colors.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'call_screen.dart';
import 'chat_screen.dart';

Widget _emptyState(IconData icon, String title, String sub) => Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 64, color: kPrimary.withValues(alpha: .35)),
        const SizedBox(height: 12),
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 4),
        Text(sub, style: const TextStyle(color: kGrey)),
      ]),
    );

class CallsPage extends StatefulWidget {
  const CallsPage({super.key});
  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  late Future<List<Map>> future = store.callLog(markAsRead: true);

  Widget _tile(Map c) {
    final out = c['outgoing'] == true;
    final st = c['status'] as String;
    final missed = !out && (st == 'missed' || st == 'ringing');
    final label =
        '${out ? 'Outgoing' : 'Incoming'}${st == 'missed' ? ' · Missed' : st == 'declined' ? ' · Declined' : ''}';
    final name = c['otherName'] as String;
    final id = c['otherUserId'] as int;
    final video = c['video'] == true;
    return ListTile(
      leading: Avatar(
        name,
        imageUrl: store.avatarFor(id, c['avatarUrl'] as String?),
      ),
      title: Text(name,
          style: TextStyle(
              fontWeight: FontWeight.w700,
              color: missed ? const Color(0xFFEF4444) : kText)),
      subtitle: Row(children: [
        Icon(
            out
                ? Icons.call_made
                : (missed ? Icons.call_missed : Icons.call_received),
            size: 14,
            color: missed ? const Color(0xFFEF4444) : kGrey),
        const SizedBox(width: 4),
        Flexible(
            child: Text('$label · ${store.fmt(c['startedAt'] as String)}',
                style: const TextStyle(color: kGrey, fontSize: 12))),
      ]),
      trailing: IconButton(
        icon: Icon(video ? Icons.videocam_outlined : Icons.call_outlined,
            color: kPrimary),
        onPressed: () => startCall(context, id, name, video),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(children: [
              const Text('Calls',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, color: kPrimary),
                onPressed: () =>
                    setState(() => future = store.callLog(markAsRead: true)),
              ),
            ]),
          ),
          Expanded(
            child: FutureBuilder<List<Map>>(
              future: future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return const Center(
                      child: Text('Cannot reach the server',
                          style: TextStyle(color: kGrey)));
                }
                final list = snap.data ?? [];
                if (list.isEmpty) {
                  return _emptyState(Icons.call_outlined, 'No calls yet',
                      'Open a chat and tap the call button');
                }
                return ListView(children: [for (final c in list) _tile(c)]);
              },
            ),
          ),
        ]),
      );
}

class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key});
  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  late Future<List<Map>> future = store.search('');

  Future<void> _open(Map u) async {
    try {
      final c = await store.openDirect(u['id'] as int);
      if (mounted) go(context, ChatScreen(chat: c));
    } catch (_) {
      if (mounted) snack(context, 'Could not open the chat');
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Text('People',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              onChanged: (v) => setState(() => future = store.search(v.trim())),
              decoration: InputDecoration(
                hintText: 'Search people...',
                prefixIcon: const Icon(Icons.search, color: kGrey),
                filled: true,
                fillColor: kBg,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map>>(
              future: future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return const Center(
                      child: Text('Cannot reach the server',
                          style: TextStyle(color: kGrey)));
                }
                final list = snap.data ?? [];
                if (list.isEmpty) {
                  return _emptyState(Icons.people_outline, 'No one here yet',
                      'Other users will appear here');
                }
                return ListView(children: [
                  for (final u in list)
                    ListTile(
                      onTap: () => _open(u),
                      leading: Avatar(
                        u['displayName'] as String,
                        online: u['online'] == true,
                        imageUrl: store.avatarFor(
                            u['id'] as int, u['avatarUrl'] as String?),
                      ),
                      title: Text(u['displayName'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('@${u['username']}',
                          style: const TextStyle(color: kGrey)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon:
                              const Icon(Icons.call_outlined, color: kPrimary),
                          onPressed: () => startCall(context, u['id'] as int,
                              u['displayName'] as String, false),
                        ),
                        IconButton(
                          icon: const Icon(Icons.videocam_outlined,
                              color: kPrimary),
                          onPressed: () => startCall(context, u['id'] as int,
                              u['displayName'] as String, true),
                        ),
                      ]),
                    ),
                ]);
              },
            ),
          ),
        ]),
      );
}
