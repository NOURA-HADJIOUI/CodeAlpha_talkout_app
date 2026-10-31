import 'dart:async';
import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});
  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  List<Map> results = [];
  bool loading = false, searched = false;
  String? error;
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _t?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        results = [];
        searched = false;
        error = null;
      });
      return;
    }
    _t = Timer(const Duration(milliseconds: 300), () async {
      setState(() => loading = true);
      try {
        final r = await store.search(q.trim());
        if (mounted) {
          setState(() {
            results = r;
            searched = true;
            error = null;
          });
        }
      } catch (_) {
        if (mounted) setState(() => error = 'Cannot reach the server');
      }
      if (mounted) setState(() => loading = false);
    });
  }

  Future<void> _open(Map u) async {
    try {
      final c = await store.openDirect(u['id'] as int);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(chat: c)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the chat')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (error != null) {
      body = Center(child: Text(error!, style: const TextStyle(color: kGrey)));
    } else if (results.isEmpty) {
      body = Center(
        child: Text(searched ? 'No users found' : 'Type a name or username to find people',
            style: const TextStyle(color: kGrey)),
      );
    } else {
      body = ListView(children: [
        for (final u in results)
          ListTile(
            onTap: () => _open(u),
            leading: Avatar(
              u['displayName'] as String,
              online: u['online'] == true,
              imageUrl: store.avatarFor(u['id'] as int, u['avatarUrl'] as String?),
            ),
            title: Text(u['displayName'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('@${u['username']}', style: const TextStyle(color: kGrey)),
          ),
      ]);
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: TextField(
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(hintText: 'Search people...', border: InputBorder.none),
        ),
        bottom: loading ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: body,
    );
  }
}