import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat.dart';
import '../theme/colors.dart';
import '../widgets/attachments.dart';

class MediaScreen extends StatefulWidget {
  final Chat? chat; // null = tous les chats chargés
  const MediaScreen({super.key, this.chat});
  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  int tab = 0;

  List<Msg> get _all =>
      widget.chat != null ? widget.chat!.messages : [for (final c in store.chats) ...c.messages];

  Widget _empty() => const Center(child: Text('Nothing shared yet', style: TextStyle(color: kGrey)));

  void _open(String u) => launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);

  Widget _body() {
    final all = _all;
    if (tab == 0) {
      final imgs = all.where((m) => m.type == 'image' && m.url != null).toList();
      if (imgs.isEmpty) return _empty();
      return GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        padding: const EdgeInsets.all(16),
        children: [
          for (final m in imgs)
            GestureDetector(
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => ImageViewer(url: store.url(m.url!)))),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(store.url(m.url!), fit: BoxFit.cover),
              ),
            ),
        ],
      );
    }
    if (tab == 1) {
      final files = all.where((m) => m.type == 'file' && m.url != null).toList();
      if (files.isEmpty) return _empty();
      return ListView(padding: const EdgeInsets.all(16), children: [
        for (final m in files)
          ListTile(
            leading: const Icon(Icons.insert_drive_file, color: kPrimary),
            title: Text(m.fileName ?? 'File'),
            subtitle: Text(m.time),
            onTap: () => _open(store.url(m.url!)),
          ),
      ]);
    }
    final re = RegExp(r'https?://\S+');
    final links = [
      for (final m in all.where((m) => m.type == 'text')) ...re.allMatches(m.text).map((x) => x.group(0)!),
    ];
    if (links.isEmpty) return _empty();
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final l in links)
        ListTile(
          leading: const Icon(Icons.link, color: kPrimary),
          title: Text(l, style: const TextStyle(color: kPrimary)),
          onTap: () => _open(l),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Media & Files', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => tab = i),
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tab == i ? kPrimary : kBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(['Media', 'Files', 'Links'][i],
                          style: TextStyle(color: tab == i ? Colors.white : kPrimary, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
            ]),
          ),
          Expanded(child: _body()),
        ]),
      );
}