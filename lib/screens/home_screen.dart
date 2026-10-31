import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../theme/colors.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'calls_people.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int i = 0;

  @override
  void initState() {
    super.initState();
    store.refreshMissedCallCount();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const ChatsPage(),
      const CallsPage(),
      const PeoplePage(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: pages[i],
      bottomNavigationBar: ListenableBuilder(
        listenable: store,
        builder: (context, _) => BottomNavigationBar(
          currentIndex: i,
          onTap: (v) => setState(() => i = v),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: kPrimary,
          unselectedItemColor: kGrey,
          items: [
            BottomNavigationBarItem(
              icon: _navigationIcon(
                  Icons.chat_bubble_outline, store.unreadMessageCount),
              label: 'Chats',
            ),
            BottomNavigationBarItem(
              icon: _navigationIcon(Icons.call_outlined, store.missedCallCount),
              label: 'Calls',
            ),
            const BottomNavigationBarItem(
                icon: Icon(Icons.people_outline), label: 'People'),
            const BottomNavigationBarItem(
                icon: Icon(Icons.settings_outlined), label: 'Settings'),
          ],
        ),
      ),
    );
  }

  Widget _navigationIcon(IconData icon, int count) => count <= 0
      ? Icon(icon)
      : Badge(
          label: Text(count > 99 ? '99+' : '$count'),
          child: Icon(icon),
        );
}

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});
  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  String query = '';

  void _newChat() => go(context, const NewChatScreen());

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(children: [
            const Logo(size: 30),
            const SizedBox(width: 8),
            const Brand(size: 20),
            const Spacer(),
            GestureDetector(
              onTap: _newChat,
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                    color: kPrimary, shape: BoxShape.circle),
                child: const Icon(Icons.add, color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search chats...',
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
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final list = store.chats
                  .where((c) => c.name.toLowerCase().contains(query))
                  .toList();
              if (list.isEmpty) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.chat_bubble_outline,
                        size: 64, color: kPrimary.withValues(alpha: .35)),
                    const SizedBox(height: 12),
                    const Text('No chats yet',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 4),
                    const Text('Tap + to find people and start chatting',
                        style: TextStyle(color: kGrey)),
                  ]),
                );
              }
              return ListView(children: [for (final c in list) ChatTile(c)]);
            },
          ),
        ),
      ]),
    );
  }
}

class ChatTile extends StatelessWidget {
  final Chat c;
  const ChatTile(this.c, {super.key});
  @override
  Widget build(BuildContext context) => ListTile(
        onTap: () => go(context, ChatScreen(chat: c)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        leading: Avatar(
          c.name,
          online: c.online,
          imageUrl: store.avatarFor(c.otherUserId, c.avatarUrl),
        ),
        title: Text(c.name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: Text(c.last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: kGrey, fontSize: 13)),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(c.time, style: const TextStyle(color: kGrey, fontSize: 11)),
            if (c.unread > 0)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(6),
                decoration:
                    const BoxDecoration(color: kGreen, shape: BoxShape.circle),
                child: Text('${c.unread}',
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
          ],
        ),
      );
}
