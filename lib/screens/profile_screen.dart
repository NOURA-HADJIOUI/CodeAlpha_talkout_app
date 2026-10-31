import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../theme/colors.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'media_screen.dart';
import 'splash_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uploadingPhoto = false;

  Future<void> _showPhotoOptions() async {
    final hasPhoto = store.avatarUrl != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(hasPhoto ? 'Change profile photo' : 'Add profile photo'),
            onTap: () => Navigator.pop(context, 'change'),
          ),
          if (hasPhoto)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Remove profile photo',
                  style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
        ]),
      ),
    );
    if (!mounted) return;
    if (action == 'change') {
      await _changePhoto();
    } else if (action == 'remove') {
      await _removePhoto();
    }
  }

  Future<void> _changePhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes ??
          (file.path != null ? await XFile(file.path!).readAsBytes() : null);
      if (bytes == null || bytes.isEmpty) {
        throw 'Could not read the selected photo';
      }
      if (bytes.length > 25 * 1024 * 1024) {
        throw 'Photo must be 25 MB or smaller';
      }
      if (!mounted) return;
      setState(() => _uploadingPhoto = true);
      await store.updateProfilePhoto(bytes, file.name);
      if (mounted) snack(context, 'Profile photo updated');
    } catch (error) {
      if (mounted) snack(context, 'Could not update profile photo: $error');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove profile photo?'),
        content: const Text('Your profile will show your initial instead.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _uploadingPhoto = true);
    try {
      await store.removeProfilePhoto();
      if (mounted) snack(context, 'Profile photo removed');
    } catch (error) {
      if (mounted) snack(context, 'Could not remove profile photo: $error');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Widget _row(BuildContext context, IconData icon, String label,
          {Widget? page}) =>
      ListTile(
        leading: Icon(icon, color: kText),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right, color: kGrey),
        onTap: () => go(context, page!),
      );

  Future<void> _editName(BuildContext context) async {
    final ctrl = TextEditingController(text: store.userName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kPrimary),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) store.rename(name);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) => ListView(padding: EdgeInsets.zero, children: [
            SizedBox(
              height: 218,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  height: 170,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF3B2A7A),
                        Color(0xFFE8704F),
                        Color(0xFFF6B26B)
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: _uploadingPhoto ? null : _showPhotoOptions,
                          customBorder: const CircleBorder(),
                          child: SizedBox(
                            width: 90,
                            height: 90,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Avatar(
                                    store.userName,
                                    size: 90,
                                    imageUrl: store.avatarFor(store.myId),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: kPrimary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: Center(
                                      child: _uploadingPhoto
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.add,
                                              color: Colors.white,
                                            ),
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
              ]),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _editName(context),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(store.userName,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
            ),
            const Center(
                child: Text('Online',
                    style: TextStyle(color: kGreen, fontSize: 13))),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(children: [
                Text('About', style: TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('Good vibes only ✨', style: TextStyle(color: kGrey)),
            ),
            const Divider(height: 28, indent: 20, endIndent: 20),
            _row(context, Icons.storage_outlined, 'Data & Storage',
                page: const MediaScreen()),
            _row(context, Icons.help_outline, 'Help & Support',
                page: const HelpScreen()),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFFEF4444)),
              title: const Text('Log out',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: Color(0xFFEF4444))),
              onTap: () async {
                await store.logout();
                if (!context.mounted) return;
                Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const SplashScreen()),
                    (r) => false);
              },
            ),
          ]));
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const faq = [
    (
      'How do I start a chat?',
      'Go to Chats, tap + and search for a person by name or username. Open the conversation and send your first message. A chat appears in your list after the first message.'
    ),
    (
      'How do I send a voice message?',
      'Tap the microphone in a chat to start recording, then tap the send button. Tap the bin to cancel.'
    ),
    (
      'How do I send photos and files?',
      'Tap + in the message bar and choose Photo or File (25 MB maximum).'
    ),
    (
      'How do I delete a message?',
      'Long-press a message. You can delete it only for yourself, or delete your own message for everyone. Deleting a message for everyone also removes its attached media or file.'
    ),
    (
      'How do calls work?',
      'Tap the phone or camera icon in a chat, in People or in Calls. Both accounts must be online and connected to the same server. Allow microphone and camera access when asked. Calls across different networks may require a TURN relay.'
    ),
    (
      'What do the ticks mean?',
      'One tick means the message was sent. Two ticks mean the other person has read it.'
    ),
    (
      'The app says it cannot reach the server',
      'Check that the server is running and that the server address on the login screen is correct.'
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Help & Support',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          for (final f in faq)
            ExpansionTile(
              shape: const Border(),
              title: Text(f.$1,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.$2, style: const TextStyle(color: kGrey, height: 1.4))
              ],
            ),
        ]),
      );
}
