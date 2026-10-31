import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/chat.dart';
import '../theme/colors.dart';
import '../utils.dart';
import '../widgets/common.dart';

void startCall(BuildContext context, int peerId, String name, bool video) {
  if (store.inCall) return;
  store.inCall = true;
  store.early.clear();
  go(context, CallScreen(peerId: peerId, peerName: name, video: video));
}

class CallScreen extends StatefulWidget {
  final int peerId;
  final String peerName;
  final bool video;
  final Map<String, dynamic>? offer; // non nul = appel entrant
  const CallScreen(
      {super.key,
      required this.peerId,
      required this.peerName,
      required this.video,
      this.offer});
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final localR = RTCVideoRenderer();
  final remoteR = RTCVideoRenderer();
  RTCPeerConnection? pc;
  MediaStream? local;
  StreamSubscription? sub;
  Timer? timer;
  Timer? ackTimer;
  int? callId;
  int sec = 0;
  bool connected = false,
      ended = false,
      mute = false,
      camOff = false,
      speaker = false;
  bool remoteReady = false, remoteSet = false;
  late bool ringing = widget.offer != null;
  String status = '';
  final List<Map<String, dynamic>> pendingIce = [];

  bool get incoming => widget.offer != null;

  @override
  void initState() {
    super.initState();
    status = incoming
        ? 'Incoming ${widget.video ? 'video' : 'audio'} call'
        : 'Calling...';
    callId = widget.offer?['callId'] as int?;
    _init();
  }

  Future<void> _init() async {
    await localR.initialize();
    await remoteR.initialize();
    sub = store.callStream.stream.listen(_onEvent);
    for (final m in List.of(store.early)) {
      _onEvent(m);
    }
    store.early.clear();
    if (!incoming) await _startOutgoing();
  }

  Future<bool> _createPc() async {
    try {
      local = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
        'audio': true,
        'video': widget.video ? <String, dynamic>{'facingMode': 'user'} : false,
      });
      localR.srcObject = local;
      pc = await createPeerConnection(<String, dynamic>{
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ],
      });
      for (final t in local!.getTracks()) {
        await pc!.addTrack(t, local!);
      }
      pc!.onIceCandidate = (c) {
        if (c.candidate == null) return;
        store.emit('call:ice',
            {'to': widget.peerId, 'callId': callId, 'candidate': c.toMap()});
      };
      pc!.onTrack = (e) {
        if (e.streams.isNotEmpty) {
          remoteR.srcObject = e.streams[0];
          if (mounted) setState(() => remoteReady = true);
        }
      };
      pc!.onConnectionState = (s) {
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected)
          _onConnected();
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed)
          _fail('Connection failed');
      };
      if (mounted) setState(() {});
      return true;
    } catch (_) {
      _fail('Could not access the microphone or camera');
      return false;
    }
  }

  Future<void> _startOutgoing() async {
    if (!store.connected) {
      _finish('Cannot reach the server');
      return;
    }
    if (!await _createPc()) return;
    try {
      final offer = await pc!.createOffer();
      await pc!.setLocalDescription(offer);
      var acknowledged = false;
      store.emitAck('call:offer', {
        'to': widget.peerId,
        'video': widget.video,
        'sdp': offer.sdp,
        'type': offer.type,
      }, (res) {
        acknowledged = true;
        ackTimer?.cancel();
        if (res is Map && res['ok'] == true) {
          callId = res['callId'] as int?;
          if (mounted) setState(() => status = 'Ringing...');
        } else {
          _finish(res is Map && res['error'] == 'offline'
              ? 'User is offline'
              : 'Could not start the call');
        }
      });
      if (!acknowledged) {
        ackTimer = Timer(const Duration(seconds: 10), () {
          if (!acknowledged) _finish('No response from the server');
        });
      }
    } catch (_) {
      _fail('Could not start the call');
    }
  }

  Future<void> _accept() async {
    setState(() {
      ringing = false;
      status = 'Connecting...';
    });
    if (!await _createPc()) return;
    try {
      final o = widget.offer!;
      await pc!.setRemoteDescription(
          RTCSessionDescription(o['sdp'] as String, o['type'] as String));
      remoteSet = true;
      await _flushIce();
      final answer = await pc!.createAnswer();
      await pc!.setLocalDescription(answer);
      store.emit('call:answer', {
        'to': widget.peerId,
        'callId': callId,
        'sdp': answer.sdp,
        'type': answer.type
      });
    } catch (_) {
      _fail('Could not answer the call');
    }
  }

  Future<void> _addIce(Map<String, dynamic> m) async {
    final c = m['candidate'] as Map;
    try {
      await pc!.addCandidate(RTCIceCandidate(c['candidate'] as String?,
          c['sdpMid'] as String?, c['sdpMLineIndex'] as int?));
    } catch (_) {}
  }

  Future<void> _flushIce() async {
    for (final m in List.of(pendingIce)) {
      await _addIce(m);
    }
    pendingIce.clear();
  }

  Future<void> _onEvent(Map<String, dynamic> m) async {
    if (ended) return;
    switch (m['event'] as String) {
      case 'call:answer':
        await pc?.setRemoteDescription(
            RTCSessionDescription(m['sdp'] as String, m['type'] as String));
        remoteSet = true;
        await _flushIce();
        if (mounted) setState(() => status = 'Connecting...');
        break;
      case 'call:ice':
        if (pc == null || !remoteSet) {
          pendingIce.add(m);
        } else {
          await _addIce(m);
        }
        break;
      case 'call:reject':
        _finish('Call declined');
        break;
      case 'call:end':
        _finish('Call ended');
        break;
    }
  }

  void _onConnected() {
    if (connected || ended) return;
    connected = true;
    status = 'Connected';
    speaker = widget.video;
    if (!kIsWeb) Helper.setSpeakerphoneOn(speaker);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => sec++);
    });
    if (mounted) setState(() {});
  }

  void _hangup() {
    store.emit(ringing ? 'call:reject' : 'call:end',
        {'to': widget.peerId, 'callId': callId});
    _finish('');
  }

  void _fail(String msg) {
    store.emit('call:end', {'to': widget.peerId, 'callId': callId});
    _finish(msg);
  }

  Future<void> _finish(String msg) async {
    if (ended) return;
    ended = true;
    timer?.cancel();
    ackTimer?.cancel();
    sub?.cancel();
    store.inCall = false;
    store.early.clear();
    for (final t in local?.getTracks() ?? <MediaStreamTrack>[]) {
      t.stop();
    }
    await pc?.close();
    if (!mounted) return;
    setState(() => status = msg);
    if (msg.isNotEmpty) await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    timer?.cancel();
    ackTimer?.cancel();
    sub?.cancel();
    store.inCall = false;
    for (final t in local?.getTracks() ?? <MediaStreamTrack>[]) {
      t.stop();
    }
    pc?.close();
    localR.dispose();
    remoteR.dispose();
    super.dispose();
  }

  void _toggleMute() {
    mute = !mute;
    for (final t in local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !mute;
    }
    setState(() {});
  }

  void _toggleCam() {
    camOff = !camOff;
    for (final t in local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !camOff;
    }
    setState(() {});
  }

  void _toggleSpeaker() {
    speaker = !speaker;
    if (!kIsWeb) Helper.setSpeakerphoneOn(speaker);
    setState(() {});
  }

  void _flip() {
    final v = local?.getVideoTracks();
    if (v != null && v.isNotEmpty) Helper.switchCamera(v.first);
  }

  String get clock =>
      '${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';

  Widget _btn(IconData icon, String label, bool on, VoidCallback onTap) =>
      Column(children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? Colors.white : Colors.white.withValues(alpha: .15),
            ),
            child: Icon(icon, color: on ? kText : Colors.white),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]);

  Widget _round(IconData icon, Color color, VoidCallback onTap) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 30),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final remoteVideo = widget.video && remoteReady;
    return Scaffold(
      backgroundColor: const Color(0xFF17171C),
      body: Stack(children: [
        if (remoteVideo)
          Positioned.fill(
            child: RTCVideoView(remoteR,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
          ),
        SafeArea(
          child: Column(children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: widget.video && connected
                    ? IconButton(
                        onPressed: _flip,
                        icon: const Icon(Icons.flip_camera_ios_outlined,
                            color: Colors.white))
                    : const SizedBox(height: 48),
              ),
            ),
            if (!remoteVideo) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3)),
                child: Avatar(
                  widget.peerName,
                  size: 150,
                  imageUrl: store.avatarFor(widget.peerId),
                ),
              ),
              const SizedBox(height: 20),
            ],
            Text(widget.peerName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(connected ? clock : status,
                style: const TextStyle(color: Colors.white70)),
            const Spacer(),
            if (ringing)
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _round(Icons.call_end, const Color(0xFFEF4444), _hangup),
                _round(Icons.call, kGreen, _accept),
              ])
            else ...[
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _btn(mute ? Icons.mic_off : Icons.mic_none, 'Mute', mute,
                    _toggleMute),
                if (widget.video)
                  _btn(camOff ? Icons.videocam_off : Icons.videocam, 'Video',
                      camOff, _toggleCam),
                if (!kIsWeb)
                  _btn(Icons.volume_up_outlined, 'Speaker', speaker,
                      _toggleSpeaker),
              ]),
              const SizedBox(height: 36),
              _round(Icons.call_end, const Color(0xFFEF4444), _hangup),
            ],
            const SizedBox(height: 40),
          ]),
        ),
        if (widget.video && local != null && !camOff)
          Positioned(
            right: 16,
            top: 90,
            width: 110,
            height: 150,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: RTCVideoView(localR,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
            ),
          ),
      ]),
    );
  }
}
