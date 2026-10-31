import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../screens/call_screen.dart';
import '../utils.dart';

class Msg {
  final int id;
  final String text, time, type;
  final bool mine;
  final int? senderId;
  final String? sender, senderAvatarUrl, url, fileName;
  Msg(this.text, this.time,
      {this.id = 0,
      this.mine = false,
      this.senderId,
      this.sender,
      this.senderAvatarUrl,
      this.type = 'text',
      this.url,
      this.fileName});
}

class Chat {
  final int id;
  final String name;
  final bool group;
  final int? otherUserId;
  bool online, typing = false, loaded = false;
  int unread, otherLastRead;
  String? avatarUrl;
  String lastText, lastTime;
  final List<Msg> messages = [];
  Chat(this.id, this.name,
      {this.group = false,
      this.otherUserId,
      this.online = false,
      this.unread = 0,
      this.otherLastRead = 0,
      this.avatarUrl,
      this.lastText = '',
      this.lastTime = ''});

  String get last => lastText.isEmpty ? 'Say hi 👋' : lastText;
  String get time => lastTime;
}

class AppStore extends ChangeNotifier {
  String serverUrl = 'http://10.0.2.2:3000';
  String? token;
  int myId = 0;
  int missedCallCount = 0;
  String userName = 'You';
  String? avatarUrl;
  final Map<int, String?> userAvatars = {};
  final List<Chat> chats = [];
  Chat? current;
  io.Socket? _socket;

  // appels
  bool inCall = false;
  final callStream = StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> early = [];

  bool get loggedIn => token != null;
  bool get connected => _socket?.connected ?? false;
  int get unreadMessageCount =>
      chats.fold(0, (total, chat) => total + chat.unread);

  void rename(String n) {
    userName = n;
    notifyListeners();
  }

  String url(String p) => p.startsWith('http') ? p : '$serverUrl$p';
  String? avatarFor(int? userId, [String? fallback]) {
    final path = userId == myId
        ? avatarUrl
        : (userAvatars.containsKey(userId) ? userAvatars[userId] : fallback);
    return path == null ? null : url(path);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _req(String method, String path,
      [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$serverUrl$path');
    final res = switch (method) {
      'GET' => await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10)),
      'DELETE' => await http
          .delete(uri, headers: _headers, body: jsonEncode(body ?? {}))
          .timeout(const Duration(seconds: 10)),
      _ => await http
          .post(uri, headers: _headers, body: jsonEncode(body ?? {}))
          .timeout(const Duration(seconds: 10)),
    };
    dynamic data;
    try {
      data = jsonDecode(res.body);
    } on FormatException {
      if (res.statusCode >= 400) {
        if (res.statusCode == 404) {
          throw 'Backend is outdated (HTTP 404). Restart the TalkOut server.';
        }
        throw 'Server error (${res.statusCode})';
      }
      rethrow;
    }
    if (res.statusCode == 401 && token != null) await logout();
    if (res.statusCode >= 400) {
      throw (data is Map && data['error'] != null
          ? data['error'].toString()
          : 'Error');
    }
    return data;
  }

  // ---------- Session ----------
  Future<void> restore() async {
    final p = await SharedPreferences.getInstance();
    serverUrl = p.getString('server') ?? serverUrl;
    token = p.getString('token');
    myId = p.getInt('myId') ?? 0;
    userName = p.getString('name') ?? 'You';
    avatarUrl = p.getString('avatarUrl');
    if (token != null) {
      _connect();
      loadChats();
      _loadProfile();
    }
  }

  Future<void> auth(
      bool signup, String user, String pass, String display) async {
    final data = await _req('POST', signup ? '/api/register' : '/api/login',
        {'username': user, 'password': pass, 'displayName': display});
    token = data['token'] as String;
    myId = data['user']['id'] as int;
    userName = data['user']['displayName'] as String;
    avatarUrl = data['user']['avatarUrl'] as String?;
    final p = await SharedPreferences.getInstance();
    await p.setString('server', serverUrl);
    await p.setString('token', token!);
    await p.setInt('myId', myId);
    await p.setString('name', userName);
    if (avatarUrl != null) {
      await p.setString('avatarUrl', avatarUrl!);
    } else {
      await p.remove('avatarUrl');
    }
    _connect();
    await loadChats();
    notifyListeners();
  }

  Future<void> logout() async {
    _socket?.dispose();
    _socket = null;
    token = null;
    current = null;
    inCall = false;
    early.clear();
    chats.clear();
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
    notifyListeners();
  }

  // ---------- Données ----------
  String fmt(String iso) {
    final d = DateTime.parse(iso).toLocal();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _preview(Map m) {
    switch (m['type']) {
      case 'voice':
        return '🎤 Voice message';
      case 'image':
        return '📷 Photo';
      case 'file':
        return '📎 ${m['fileName'] ?? 'File'}';
      default:
        return m['body'] as String? ?? '';
    }
  }

  Msg _msg(Map m) =>
      Msg(m['body'] as String? ?? '', fmt(m['createdAt'] as String),
          id: m['id'] as int,
          mine: m['senderId'] == myId,
          senderId: m['senderId'] as int?,
          sender: m['senderName'] as String?,
          senderAvatarUrl: m['senderAvatarUrl'] as String?,
          type: m['type'] as String? ?? 'text',
          url: m['fileUrl'] as String?,
          fileName: m['fileName'] as String?);

  Chat? _find(int id) {
    for (final c in chats) {
      if (c.id == id) return c;
    }
    return null;
  }

  Chat? _any(int id) => _find(id) ?? (current?.id == id ? current : null);

  Chat _chatFrom(Map j) {
    var c = _find(j['id'] as int);
    c ??= Chat(j['id'] as int, j['name'] as String,
        group: j['type'] == 'group', otherUserId: j['otherUserId'] as int?);
    c.online = j['online'] == true;
    c.avatarUrl = j['avatarUrl'] as String?;
    if (c.otherUserId != null) userAvatars[c.otherUserId!] = c.avatarUrl;
    c.unread = j['unread'] as int;
    c.otherLastRead = j['otherLastRead'] as int;
    final last = j['last'];
    if (last != null) {
      c.lastText =
          '${last['senderId'] == myId ? 'You: ' : ''}${_preview(last as Map)}';
      c.lastTime = fmt(last['createdAt'] as String);
    } else {
      c.lastText = '';
      c.lastTime = '';
    }
    return c;
  }

  Future<void> loadChats() async {
    try {
      final list = await _req('GET', '/api/conversations') as List;
      final fresh = [for (final j in list) _chatFrom(j as Map)];
      chats
        ..clear()
        ..addAll(fresh);
      notifyListeners();
    } catch (_) {}
  }

  Future<List<Map>> search(String q) async {
    final r =
        await _req('GET', '/api/users/search?q=${Uri.encodeQueryComponent(q)}')
            as List;
    final users = [for (final u in r) u as Map];
    for (final user in users) {
      userAvatars[user['id'] as int] = user['avatarUrl'] as String?;
    }
    return users;
  }

  Future<List<Map>> callLog({bool markAsRead = false}) async {
    final r = await _req('GET', '/api/calls') as List;
    final calls = [for (final c in r) c as Map];
    final prefs = await SharedPreferences.getInstance();
    final seenKey = 'lastSeenCallId_$myId';
    final lastSeenCallId = prefs.getInt(seenKey) ?? 0;
    final missed = calls.where((call) =>
        call['outgoing'] != true &&
        (call['status'] == 'missed' || call['status'] == 'ringing'));
    if (markAsRead) {
      final latestCallId = calls.fold<int>(
        lastSeenCallId,
        (latest, call) =>
            (call['id'] as int) > latest ? call['id'] as int : latest,
      );
      await prefs.setInt(seenKey, latestCallId);
      missedCallCount = 0;
    } else {
      missedCallCount =
          missed.where((call) => (call['id'] as int) > lastSeenCallId).length;
    }
    notifyListeners();
    return calls;
  }

  Future<void> refreshMissedCallCount() async {
    try {
      await callLog();
    } catch (error) {
      debugPrint('Could not refresh missed call count: $error');
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _req('GET', '/api/me') as Map;
      avatarUrl = profile['avatarUrl'] as String?;
      if (avatarUrl == null) {
        await (await SharedPreferences.getInstance()).remove('avatarUrl');
      } else {
        await (await SharedPreferences.getInstance())
            .setString('avatarUrl', avatarUrl!);
      }
      notifyListeners();
    } catch (_) {
      // Keep the locally cached profile while the server is unavailable.
    }
  }

  Future<void> updateProfilePhoto(List<int> bytes, String name) async {
    if (token == null) {
      throw 'You must be logged in to update your profile photo';
    }
    final request = http.MultipartRequest(
        'POST', Uri.parse('$serverUrl/api/profile/photo'))
      ..headers['Authorization'] = _headers['Authorization'] ?? ''
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: name));
    final response = await http.Response.fromStream(
      await request.send().timeout(const Duration(seconds: 60)),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw (data is Map && data['error'] != null
              ? data['error']
              : 'Photo upload failed')
          .toString();
    }
    avatarUrl = (data as Map)['avatarUrl'] as String?;
    if (avatarUrl != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('avatarUrl', avatarUrl!);
    }
    userAvatars[myId] = avatarUrl;
    notifyListeners();
  }

  Future<void> removeProfilePhoto() async {
    await _req('DELETE', '/api/profile/photo');
    avatarUrl = null;
    userAvatars[myId] = null;
    await (await SharedPreferences.getInstance()).remove('avatarUrl');
    notifyListeners();
  }

  Future<Chat> openDirect(int userId) async {
    final j =
        await _req('POST', '/api/conversations/direct', {'userId': userId})
            as Map;
    return _chatFrom(j);
  }

  Future<void> openChat(Chat c) async {
    current = c;
    if (!c.loaded) await _loadMessages(c);
    markRead(c);
  }

  void closeChat(Chat c) {
    if (current == c) current = null;
  }

  Future<void> _loadMessages(Chat c) async {
    try {
      final list =
          await _req('GET', '/api/conversations/${c.id}/messages') as List;
      c.messages
        ..clear()
        ..addAll([for (final m in list) _msg(m as Map)]);
      c.loaded = true;
      notifyListeners();
    } catch (_) {}
  }

  void markRead(Chat c) {
    c.unread = 0;
    _socket?.emit('messages:read', {'conversationId': c.id});
    notifyListeners();
  }

  bool send(Chat c, String text) {
    if (!connected) return false;
    _socket!.emit('message:send', {'conversationId': c.id, 'body': text});
    return true;
  }

  /// Envoie une photo, un fichier ou un message vocal (type: image | file | voice).
  Future<void> sendFile(Chat c, String type, List<int> bytes, String name,
      {String body = ''}) async {
    if (!connected) throw 'Not connected to the server';
    final req = http.MultipartRequest(
        'POST', Uri.parse('$serverUrl/api/upload'))
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: name));
    final res = await http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 60)));
    final data = jsonDecode(res.body);
    if (res.statusCode >= 400) {
      throw (data['error'] ?? 'Upload failed').toString();
    }
    _socket!.emit('message:send', {
      'conversationId': c.id,
      'type': type,
      'fileUrl': data['url'],
      'fileName': data['name'],
      'fileSize': data['size'],
      'body': body,
    });
  }

  Future<void> deleteMessage(Chat c, Msg message,
      {required bool forEveryone}) async {
    await _req('DELETE', '/api/messages/${message.id}', {
      'mode': forEveryone ? 'everyone' : 'me',
    });
    _onMessageRemoved({
      'conversationId': c.id,
      'messageId': message.id,
    });
  }

  void typing(Chat c, bool on) =>
      _socket?.emit('typing', {'conversationId': c.id, 'isTyping': on});

  void emit(String ev, Map<String, dynamic> data) => _socket?.emit(ev, data);

  void emitAck(
          String ev, Map<String, dynamic> data, void Function(dynamic) cb) =>
      _socket?.emitWithAck(ev, data, ack: cb);

  // ---------- Temps réel ----------
  void _connect() {
    _socket?.dispose();
    final s = io.io(
        serverUrl,
        io.OptionBuilder()
            .setTransports(['websocket']).setAuth({'token': token}).build());
    _socket = s;
    s.onConnect((_) {
      loadChats();
      if (current != null) _loadMessages(current!);
      notifyListeners();
    });
    s.onDisconnect((_) => notifyListeners());
    s.on('message:new', (d) => _onMessage(Map<String, dynamic>.from(d as Map)));
    s.on('message:hidden',
        (d) => _onMessageRemoved(Map<String, dynamic>.from(d as Map)));
    s.on('message:deleted',
        (d) => _onMessageRemoved(Map<String, dynamic>.from(d as Map)));
    s.on('profile:updated', (d) {
      final event = Map<String, dynamic>.from(d as Map);
      final userId = event['userId'] as int;
      final path = event['avatarUrl'] as String?;
      userAvatars[userId] = path;
      for (final chat in [...chats, if (current != null) current!]) {
        if (chat.otherUserId == userId) chat.avatarUrl = path;
      }
      notifyListeners();
    });
    s.on('presence', (d) {
      final m = d as Map;
      for (final c in [...chats, if (current != null) current!]) {
        if (c.otherUserId == m['userId']) c.online = m['online'] == true;
      }
      notifyListeners();
    });
    s.on('messages:read', (d) {
      final m = d as Map;
      final c = _any(m['conversationId'] as int);
      if (c != null && m['userId'] != myId) {
        c.otherLastRead = m['lastReadId'] as int;
        notifyListeners();
      }
    });
    s.on('typing', (d) {
      final m = d as Map;
      final c = _any(m['conversationId'] as int);
      if (c != null) {
        c.typing = m['isTyping'] == true;
        notifyListeners();
      }
    });
    s.on('call:offer',
        (d) => _incomingCall(Map<String, dynamic>.from(d as Map)));
    for (final ev in ['call:answer', 'call:ice', 'call:end', 'call:reject']) {
      s.on(ev, (d) {
        final m = Map<String, dynamic>.from(d as Map)..['event'] = ev;
        if (callStream.hasListener) {
          callStream.add(m);
        } else {
          early.add(m);
        }
      });
    }
  }

  void _incomingCall(Map<String, dynamic> m) {
    if (inCall) {
      emit('call:reject', {'to': m['from'], 'callId': m['callId']});
      return;
    }
    inCall = true;
    early.clear();
    navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => CallScreen(
        peerId: m['from'] as int,
        peerName: (m['fromName'] ?? 'Unknown') as String,
        video: m['video'] == true,
        offer: m,
      ),
    ));
  }

  void _onMessage(Map<String, dynamic> j) {
    final cid = j['conversationId'] as int;
    var c = _find(cid);
    if (c == null && current?.id == cid) {
      c = current;
      chats.insert(0, c!);
    }
    if (c == null) {
      loadChats();
      return;
    }
    final m = _msg(j);
    if (c.loaded && !c.messages.any((x) => x.id == m.id)) c.messages.add(m);
    c.lastText = '${m.mine ? 'You: ' : ''}${_preview(j)}';
    c.lastTime = m.time;
    c.typing = false;
    chats.remove(c);
    chats.insert(0, c);
    if (!m.mine) {
      if (current?.id == cid) {
        markRead(c);
      } else {
        c.unread++;
      }
    }
    notifyListeners();
  }

  void _onMessageRemoved(Map<String, dynamic> event) {
    final cid = event['conversationId'] as int;
    final messageId = event['messageId'] as int;
    final c = _any(cid);
    if (c != null) {
      c.messages.removeWhere((message) => message.id == messageId);
      c.loaded = false;
    }
    notifyListeners();
    loadChats();
    if (current?.id == cid) _loadMessages(current!);
  }
}

final store = AppStore();
