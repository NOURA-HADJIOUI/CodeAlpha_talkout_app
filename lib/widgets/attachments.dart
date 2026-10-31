import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class VoiceBubble extends StatefulWidget {
  final String url;
  final int seconds;
  final Color color;
  const VoiceBubble({super.key, required this.url, required this.seconds, required this.color});
  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  final player = AudioPlayer();
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<void>? _completeSub;
  bool playing = false;
  Duration duration = Duration.zero;
  Duration pos = Duration.zero;

  @override
  void initState() {
    super.initState();
    _completeSub = player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          playing = false;
          pos = Duration.zero;
        });
      }
    });
    _durationSub = player.onDurationChanged.listen((d) {
      if (mounted) setState(() => duration = d);
    });
    _positionSub = player.onPositionChanged.listen((p) {
      if (mounted) setState(() => pos = p);
    });
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    _durationSub?.cancel();
    _positionSub?.cancel();
    player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (playing) {
        await player.pause();
        if (mounted) setState(() => playing = false);
      } else {
        if (pos > Duration.zero) {
          await player.resume();
        } else {
          await player.play(UrlSource(widget.url));
        }
        if (mounted) setState(() => playing = true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => playing = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not play this voice message')),
      );
    }
  }

  String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds > 0 ? duration.inMilliseconds : widget.seconds * 1000;
    final progress = total <= 0 ? 0.0 : (pos.inMilliseconds / total).clamp(0.0, 1.0);
    final shownSeconds = duration.inMilliseconds > 0 ? duration.inSeconds : widget.seconds;
    return SizedBox(
      width: 200,
      child: Row(children: [
        GestureDetector(
          onTap: _toggle,
          child: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, color: widget.color, size: 34),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LinearProgressIndicator(
            value: progress,
            color: widget.color,
            backgroundColor: widget.color.withValues(alpha: .25),
            minHeight: 3,
          ),
        ),
        const SizedBox(width: 8),
        Text(_fmt(playing || pos > Duration.zero ? pos.inSeconds : shownSeconds),
            style: TextStyle(color: widget.color, fontSize: 12)),
      ]),
    );
  }
}

class ImageViewer extends StatelessWidget {
  final String url;
  const ImageViewer({super.key, required this.url});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(child: InteractiveViewer(child: Image.network(url))),
      );
}

class FileRow extends StatelessWidget {
  final String name, url;
  final Color color;
  const FileRow({super.key, required this.name, required this.url, required this.color});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.insert_drive_file, color: color),
          const SizedBox(width: 8),
          Flexible(child: Text(name, style: TextStyle(color: color, decoration: TextDecoration.underline))),
        ]),
      );
}