// Serveur TalkOut : API REST (comptes, recherche, discussions) + Socket.io (temps réel)
const express = require('express');
const http = require('http');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { Server } = require('socket.io');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const db = require('./db');

db.exec(`
CREATE TABLE IF NOT EXISTS calls (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  caller_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  callee_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  video       INTEGER NOT NULL DEFAULT 0,
  status      TEXT NOT NULL DEFAULT 'ringing',
  started_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  answered_at TEXT,
  ended_at    TEXT
);`);

const UPLOADS = path.join(__dirname, 'uploads');
fs.mkdirSync(UPLOADS, { recursive: true });
const upload = multer({
  storage: multer.diskStorage({
    destination: UPLOADS,
    filename: (req, file, cb) => {
      const ext = path.extname(file.originalname || '').replace(/[^.a-z0-9]/gi, '').slice(0, 10);
      cb(null, `${Date.now()}-${Math.round(Math.random() * 1e9)}${ext}`);
    },
  }),
  limits: { fileSize: 25 * 1024 * 1024 },
});

function hasSupportedImageSignature(filePath) {
  const fd = fs.openSync(filePath, 'r');
  try {
    const header = Buffer.alloc(12);
    const bytesRead = fs.readSync(fd, header, 0, header.length, 0);
    return (
      (bytesRead >= 3 && header[0] === 0xff && header[1] === 0xd8 && header[2] === 0xff) ||
      (bytesRead >= 8 && header.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) ||
      (bytesRead >= 6 && ['GIF87a', 'GIF89a'].includes(header.toString('ascii', 0, 6))) ||
      (bytesRead >= 12 &&
        header.toString('ascii', 0, 4) === 'RIFF' &&
        header.toString('ascii', 8, 12) === 'WEBP')
    );
  } finally {
    fs.closeSync(fd);
  }
}

const PORT = process.env.PORT || 3000;
const SECRET = process.env.JWT_SECRET || 'talkout-dev-secret-change-me';

const app = express();
app.use(cors());
app.use(express.json());
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });

const online = new Map(); // userId -> nombre de connexions ouvertes
const isOnline = (uid) => (online.get(uid) || 0) > 0;
db.prepare('UPDATE users SET is_online = 0').run();

const iso = (t) => (t ? t.replace(' ', 'T') + 'Z' : null);
const sign = (u) => jwt.sign({ id: u.id }, SECRET, { expiresIn: '30d' });
const publicUser = (u) => ({
  id: u.id, username: u.username, displayName: u.display_name, avatarUrl: u.avatar_url,
});
const msgQuery = `SELECT m.*, u.display_name AS sender_name, u.avatar_url AS sender_avatar_url
  FROM messages m JOIN users u ON u.id = m.sender_id`;
const msgOut = (m) => ({
  id: m.id, conversationId: m.conversation_id, senderId: m.sender_id,
  senderName: m.sender_name, senderAvatarUrl: m.sender_avatar_url,
  body: m.body, type: m.type, createdAt: iso(m.created_at),
  fileUrl: m.file_url, fileName: m.file_name, fileSize: m.file_size,
});
const members = (cid) => db.prepare('SELECT user_id FROM conversation_members WHERE conversation_id = ?').all(cid).map((r) => r.user_id);
const isMember = (cid, uid) => !!db.prepare('SELECT 1 FROM conversation_members WHERE conversation_id = ? AND user_id = ?').get(cid, uid);

function convItem(cid, me) {
  const c = db.prepare('SELECT * FROM conversations WHERE id = ?').get(cid);
  const mem = db.prepare('SELECT * FROM conversation_members WHERE conversation_id = ?').all(cid);
  const mine = mem.find((m) => m.user_id === me);
  const other = c.type === 'direct' ? mem.find((m) => m.user_id !== me) : null;
  const otherUser = other && db.prepare('SELECT display_name, avatar_url FROM users WHERE id = ?').get(other.user_id);
  const last = db.prepare(`${msgQuery}
    WHERE m.conversation_id = ? AND NOT EXISTS (
      SELECT 1 FROM hidden_messages h WHERE h.message_id = m.id AND h.user_id = ?
    ) ORDER BY m.id DESC LIMIT 1`).get(cid, me);
  const unread = db.prepare(`SELECT COUNT(*) AS n FROM messages m
    WHERE m.conversation_id = ? AND m.id > ? AND m.sender_id != ?
      AND NOT EXISTS (
        SELECT 1 FROM hidden_messages h WHERE h.message_id = m.id AND h.user_id = ?
      )`).get(cid, mine.last_read_message_id, me, me).n;
  return {
    id: cid, type: c.type, name: otherUser ? otherUser.display_name : c.name,
    otherUserId: other ? other.user_id : null,
    avatarUrl: otherUser ? otherUser.avatar_url : null,
    online: other ? isOnline(other.user_id) : false,
    unread, otherLastRead: other ? other.last_read_message_id : 0, last: last ? msgOut(last) : null,
  };
}

app.get('/health', (req, res) => res.json({ ok: true, app: 'TalkOut' }));
app.use('/uploads', express.static(UPLOADS));

// ---------- Comptes ----------
app.post('/api/register', (req, res) => {
  const { username, password, displayName } = req.body || {};
  const uname = String(username || '').trim().toLowerCase();
  if (!/^[a-z0-9_.]{3,20}$/.test(uname)) return res.status(400).json({ error: 'Username: 3-20 letters, digits, _ or .' });
  if (String(password || '').length < 6) return res.status(400).json({ error: 'Password must have at least 6 characters' });
  if (db.prepare('SELECT 1 FROM users WHERE username = ?').get(uname)) return res.status(409).json({ error: 'Username already taken' });
  const name = String(displayName || '').trim() || uname;
  const info = db.prepare('INSERT INTO users (username, email, password_hash, display_name) VALUES (?, ?, ?, ?)')
    .run(uname, `${uname}@talkout.app`, bcrypt.hashSync(String(password), 10), name);
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(info.lastInsertRowid);
  res.json({ token: sign(user), user: publicUser(user) });
});

app.post('/api/login', (req, res) => {
  const { username, password } = req.body || {};
  const user = db.prepare('SELECT * FROM users WHERE username = ?').get(String(username || '').trim().toLowerCase());
  if (!user || !bcrypt.compareSync(String(password || ''), user.password_hash)) {
    return res.status(401).json({ error: 'Wrong username or password' });
  }
  res.json({ token: sign(user), user: publicUser(user) });
});

app.use('/api', (req, res, next) => {
  try {
    req.userId = jwt.verify((req.headers.authorization || '').replace('Bearer ', ''), SECRET).id;
    if (!db.prepare('SELECT 1 FROM users WHERE id = ?').get(req.userId)) throw new Error('unknown user');
    next();
  } catch {
    res.status(401).json({ error: 'Invalid session' });
  }
});

app.get('/api/me', (req, res) => {
  const user = db.prepare('SELECT id, username, display_name, avatar_url FROM users WHERE id = ?').get(req.userId);
  res.json(publicUser(user));
});

// ---------- Fichiers, photos, messages vocaux ----------
app.post('/api/upload', (req, res) => {
  upload.single('file')(req, res, (err) => {
    if (err) return res.status(400).json({ error: err.message });
    if (!req.file) return res.status(400).json({ error: 'No file' });
    res.json({ url: `/uploads/${req.file.filename}`, name: req.file.originalname, size: req.file.size });
  });
});

app.post('/api/profile/photo', (req, res) => {
  upload.single('file')(req, res, (err) => {
    if (err) return res.status(400).json({ error: err.message });
    if (!req.file) return res.status(400).json({ error: 'No photo uploaded' });
    let isSupportedImage;
    try {
      isSupportedImage = hasSupportedImageSignature(req.file.path);
    } catch (validationError) {
      console.error('Could not validate uploaded profile photo:', validationError);
      fs.unlink(req.file.path, (unlinkError) => {
        if (unlinkError) console.error('Could not remove invalid profile photo:', unlinkError);
      });
      return res.status(500).json({ error: 'Could not validate the uploaded photo' });
    }
    if (!isSupportedImage) {
      fs.unlink(req.file.path, (unlinkError) => {
        if (unlinkError) console.error('Could not remove invalid profile photo:', unlinkError);
      });
      return res.status(400).json({ error: 'Choose a JPEG, PNG, GIF, or WebP image' });
    }

    const avatarUrl = `/uploads/${req.file.filename}`;
    db.prepare('UPDATE users SET avatar_url = ? WHERE id = ?').run(avatarUrl, req.userId);
    io.emit('profile:updated', { userId: req.userId, avatarUrl });
    res.json({ avatarUrl });
  });
});

app.delete('/api/profile/photo', (req, res) => {
  const user = db.prepare('SELECT avatar_url FROM users WHERE id = ?').get(req.userId);
  db.prepare('UPDATE users SET avatar_url = NULL WHERE id = ?').run(req.userId);

  const avatarPath = user.avatar_url;
  if (avatarPath && avatarPath.startsWith('/uploads/')) {
    const filename = path.basename(avatarPath);
    if (filename === avatarPath.slice('/uploads/'.length)) {
      fs.unlink(path.join(UPLOADS, filename), (err) => {
        if (err && err.code !== 'ENOENT') console.error('Could not delete profile photo:', err);
      });
    }
  }

  io.emit('profile:updated', { userId: req.userId, avatarUrl: null });
  res.json({ avatarUrl: null });
});

// ---------- Historique des appels ----------
app.get('/api/calls', (req, res) => {
  const rows = db.prepare(`SELECT c.*, u.display_name AS other_name, u.avatar_url AS other_avatar_url FROM calls c
    JOIN users u ON u.id = CASE WHEN c.caller_id = ? THEN c.callee_id ELSE c.caller_id END
    WHERE c.caller_id = ? OR c.callee_id = ? ORDER BY c.id DESC LIMIT 50`).all(req.userId, req.userId, req.userId);
  res.json(rows.map((c) => ({
    id: c.id, video: !!c.video, status: c.status, outgoing: c.caller_id === req.userId,
    otherUserId: c.caller_id === req.userId ? c.callee_id : c.caller_id,
    otherName: c.other_name, avatarUrl: c.other_avatar_url,
    startedAt: iso(c.started_at),
    duration: c.answered_at && c.ended_at ? Math.max(0, Math.round((Date.parse(iso(c.ended_at)) - Date.parse(iso(c.answered_at))) / 1000)) : 0,
  })));
});

// ---------- Recherche et discussions ----------
app.get('/api/users/search', (req, res) => {
  const q = `%${String(req.query.q || '').trim().toLowerCase()}%`;
  const rows = db.prepare(`SELECT id, username, display_name FROM users
    WHERE id != ? AND (lower(username) LIKE ? OR lower(display_name) LIKE ?) ORDER BY display_name LIMIT 50`).all(req.userId, q, q);
  res.json(rows.map((u) => ({ ...publicUser(u), online: isOnline(u.id) })));
});

// Seules les discussions qui contiennent au moins un message sont listées
app.get('/api/conversations', (req, res) => {
  const ids = db.prepare(`SELECT cm.conversation_id AS id FROM conversation_members cm
    WHERE cm.user_id = ? AND EXISTS (
      SELECT 1 FROM messages m WHERE m.conversation_id = cm.conversation_id
    )`).all(req.userId);
  const items = ids.map((r) => convItem(r.id, req.userId));
  items.sort((a, b) => b.last.id - a.last.id);
  res.json(items);
});

app.post('/api/conversations/direct', (req, res) => {
  const other = Number((req.body || {}).userId);
  if (!other || other === req.userId || !db.prepare('SELECT 1 FROM users WHERE id = ?').get(other)) {
    return res.status(400).json({ error: 'Invalid user' });
  }
  let row = db.prepare(`SELECT c.id FROM conversations c
    JOIN conversation_members a ON a.conversation_id = c.id AND a.user_id = ?
    JOIN conversation_members b ON b.conversation_id = c.id AND b.user_id = ?
    WHERE c.type = 'direct'`).get(req.userId, other);
  if (!row) {
    const create = db.transaction(() => {
      const id = Number(db.prepare("INSERT INTO conversations (type, created_by) VALUES ('direct', ?)").run(req.userId).lastInsertRowid);
      const add = db.prepare('INSERT INTO conversation_members (conversation_id, user_id) VALUES (?, ?)');
      add.run(id, req.userId);
      add.run(id, other);
      return id;
    });
    row = { id: create() };
  }
  res.json(convItem(row.id, req.userId));
});

app.get('/api/conversations/:id/messages', (req, res) => {
  const cid = Number(req.params.id);
  if (!isMember(cid, req.userId)) return res.status(403).json({ error: 'Forbidden' });
  const rows = db.prepare(`${msgQuery}
    WHERE m.conversation_id = ? AND NOT EXISTS (
      SELECT 1 FROM hidden_messages h WHERE h.message_id = m.id AND h.user_id = ?
    ) ORDER BY m.id DESC LIMIT 200`).all(cid, req.userId).reverse();
  res.json(rows.map(msgOut));
});

app.delete('/api/messages/:id', (req, res) => {
  const id = Number(req.params.id);
  const mode = String((req.body || {}).mode || '');
  const message = db.prepare('SELECT * FROM messages WHERE id = ?').get(id);
  if (!message || !isMember(message.conversation_id, req.userId)) {
    return res.status(404).json({ error: 'Message not found' });
  }
  if (mode === 'me') {
    db.prepare('INSERT OR IGNORE INTO hidden_messages (user_id, message_id) VALUES (?, ?)').run(req.userId, id);
    io.to(`user:${req.userId}`).emit('message:hidden', {
      conversationId: message.conversation_id, messageId: id,
    });
    return res.json({ ok: true });
  }
  if (mode !== 'everyone') return res.status(400).json({ error: 'Invalid deletion mode' });
  if (message.sender_id !== req.userId) {
    return res.status(403).json({ error: 'Only the sender can delete a message for everyone' });
  }

  const recipients = members(message.conversation_id);
  db.prepare('DELETE FROM messages WHERE id = ?').run(id);
  for (const userId of recipients) {
    io.to(`user:${userId}`).emit('message:deleted', {
      conversationId: message.conversation_id, messageId: id,
    });
  }
  const fileStillUsed = message.file_url
    && db.prepare('SELECT 1 FROM messages WHERE file_url = ? LIMIT 1').get(message.file_url);
  if (!fileStillUsed && message.file_url && /^\/uploads\/[\w.-]+$/.test(message.file_url)) {
    const filePath = path.join(UPLOADS, path.basename(message.file_url));
    fs.unlink(filePath, (err) => {
      if (err && err.code !== 'ENOENT') console.error('Could not remove deleted message file:', err);
    });
  }
  res.json({ ok: true });
});

// ---------- Temps réel ----------
io.use((socket, next) => {
  try {
    socket.userId = jwt.verify(String((socket.handshake.auth || {}).token || ''), SECRET).id;
    next();
  } catch {
    next(new Error('unauthorized'));
  }
});

io.on('connection', (socket) => {
  const uid = socket.userId;
  socket.join(`user:${uid}`);
  online.set(uid, (online.get(uid) || 0) + 1);
  db.prepare('UPDATE users SET is_online = 1 WHERE id = ?').run(uid);
  io.emit('presence', { userId: uid, online: true });

  socket.on('message:send', (data, ack) => {
    const reply = typeof ack === 'function' ? ack : () => {};
    const d = data || {};
    const cid = Number(d.conversationId);
    const type = ['text', 'image', 'file', 'voice'].includes(d.type) ? d.type : 'text';
    const body = String(d.body || '').trim();
    const fileUrl = d.fileUrl ? String(d.fileUrl) : null;
    if (!isMember(cid, uid) || body.length > 4000) return reply({ ok: false });
    if (type === 'text' ? !body : !(fileUrl && /^\/uploads\/[\w.-]+$/.test(fileUrl))) return reply({ ok: false });
    const isFile = type !== 'text';
    const info = db.prepare('INSERT INTO messages (conversation_id, sender_id, type, body, file_url, file_name, file_size) VALUES (?, ?, ?, ?, ?, ?, ?)')
      .run(cid, uid, type, body || null, isFile ? fileUrl : null, isFile ? String(d.fileName || '').slice(0, 200) || null : null, isFile ? Number(d.fileSize) || null : null);
    const msg = msgOut(db.prepare(`${msgQuery} WHERE m.id = ?`).get(info.lastInsertRowid));
    for (const m of members(cid)) io.to(`user:${m}`).emit('message:new', msg);
    reply({ ok: true, id: msg.id });
  });

  socket.on('typing', (d) => {
    const cid = Number(d && d.conversationId);
    if (!isMember(cid, uid)) return;
    for (const m of members(cid)) {
      if (m !== uid) io.to(`user:${m}`).emit('typing', { conversationId: cid, userId: uid, isTyping: !!d.isTyping });
    }
  });

  socket.on('messages:read', (d) => {
    const cid = Number(d && d.conversationId);
    if (!isMember(cid, uid)) return;
    const last = db.prepare('SELECT MAX(id) AS id FROM messages WHERE conversation_id = ?').get(cid).id || 0;
    db.prepare('UPDATE conversation_members SET last_read_message_id = ? WHERE conversation_id = ? AND user_id = ?').run(last, cid, uid);
    for (const m of members(cid)) io.to(`user:${m}`).emit('messages:read', { conversationId: cid, userId: uid, lastReadId: last });
  });

  // ----- Appels audio/vidéo (signalisation WebRTC) -----
  const me = db.prepare('SELECT display_name FROM users WHERE id = ?').get(uid).display_name;

  socket.on('call:offer', (d, ack) => {
    const reply = typeof ack === 'function' ? ack : () => {};
    const to = Number(d && d.to);
    if (!to || to === uid || !db.prepare('SELECT 1 FROM users WHERE id = ?').get(to)) return reply({ ok: false });
    const video = d.video ? 1 : 0;
    if (!isOnline(to)) {
      db.prepare("INSERT INTO calls (caller_id, callee_id, video, status, ended_at) VALUES (?, ?, ?, 'missed', CURRENT_TIMESTAMP)").run(uid, to, video);
      return reply({ ok: false, error: 'offline' });
    }
    const id = Number(db.prepare('INSERT INTO calls (caller_id, callee_id, video) VALUES (?, ?, ?)').run(uid, to, video).lastInsertRowid);
    io.to(`user:${to}`).emit('call:offer', { from: uid, fromName: me, callId: id, video: !!video, sdp: d.sdp, type: d.type });
    reply({ ok: true, callId: id });
  });

  ['call:answer', 'call:ice', 'call:reject', 'call:end'].forEach((ev) => {
    socket.on(ev, (d) => {
      const to = Number(d && d.to);
      if (!to) return;
      const callId = Number(d.callId) || null;
      const c = callId && db.prepare('SELECT * FROM calls WHERE id = ?').get(callId);
      if (c) {
        if (![c.caller_id, c.callee_id].includes(uid) || ![c.caller_id, c.callee_id].includes(to)) return;
        if (ev === 'call:answer') db.prepare("UPDATE calls SET status = 'answered', answered_at = CURRENT_TIMESTAMP WHERE id = ?").run(callId);
        if (ev === 'call:reject') db.prepare("UPDATE calls SET status = 'declined', ended_at = CURRENT_TIMESTAMP WHERE id = ?").run(callId);
        if (ev === 'call:end') db.prepare("UPDATE calls SET status = CASE WHEN status = 'ringing' THEN 'missed' ELSE status END, ended_at = COALESCE(ended_at, CURRENT_TIMESTAMP) WHERE id = ?").run(callId);
      }
      io.to(`user:${to}`).emit(ev, { ...d, from: uid, fromName: me });
    });
  });

  socket.on('disconnect', () => {
    const n = (online.get(uid) || 1) - 1;
    if (n > 0) return online.set(uid, n);
    online.delete(uid);
    db.prepare('UPDATE users SET is_online = 0, last_seen = CURRENT_TIMESTAMP WHERE id = ?').run(uid);
    io.emit('presence', { userId: uid, online: false });
  });
});

server.listen(PORT, '0.0.0.0', () => console.log(`TalkOut server running on http://localhost:${PORT}`));