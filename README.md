# TalkOut

TalkOut is a real-time messaging app built with Flutter. Users can chat, share
files and make audio or video calls. The project is made of a Flutter app and a
Node.js server backed by an SQLite database.

Built as **Task 4 (Real-Time Communication App)** of the CodeAlpha Full Stack
Development internship.

## Features

- Sign-up and login with a username and a password.
- User search and one-to-one conversations.
- Real-time messaging with presence, typing and read indicators (✓ sent, ✓✓ read).
- Unread message counter and missed-call counter.
- Photo, file and voice message sharing (25 MB maximum per file).
- Audio and video calls with WebRTC.
- Add, replace and remove the profile photo.
- Call history.
- Media, files and links shared in a conversation.
- Message deletion: delete for me, or delete your own message for everyone.
- Accounts and conversations stored in SQLite.

## Tech stack

- **App:** Flutter and Dart
- **Real time and calls:** Socket.IO and WebRTC (signaling goes through Socket.IO)
- **Server:** Node.js, Express and Socket.IO
- **Database:** SQLite with `better-sqlite3`
- **Security:** JWT sessions and bcrypt password hashing
- **Uploads:** Multer

## Prerequisites

- Flutter and Dart installed.
- Node.js 18 or later, and npm.
- An Android emulator, a connected Android device, or any Flutter-supported
  platform (for example Chrome).

## Getting started

### 1. Install and start the server

From the `backend` folder:

```bash
cd backend
npm install
npm start
```

`npm start` runs `node server.js`. You can also start the server directly:

```bash
node server.js
```

The server listens on port `3000` by default. Check that it is running by
opening `http://localhost:3000/health`: you should see `{"ok":true,"app":"TalkOut"}`.

The SQLite database (`backend/talkout.db`) and the shared files folder
(`backend/uploads`) are created automatically on the first start.

To change the port or the session signing key, set the `PORT` and `JWT_SECRET`
environment variables before starting the server:

```bash
# macOS / Linux
JWT_SECRET="a-long-random-secret" PORT=3000 node server.js

# Windows (PowerShell)
$env:JWT_SECRET="a-long-random-secret"; node server.js

# Windows (cmd)
set JWT_SECRET=a-long-random-secret&& node server.js
```

In production, always set a private and strong `JWT_SECRET`.

> `npm start` works only if `backend/package.json` contains
> `"scripts": { "start": "node server.js" }`. If it does not, use
> `node server.js`.

### 2. Install and start the app

From the project root:

```bash
flutter pub get
flutter run
```

On the login screen, expand **Server settings** and enter the server address:

- **Android emulator:** `http://10.0.2.2:3000`
- **Physical device:** `http://<your-PC-IP-address>:3000` (the phone and the PC
  must be on the same Wi-Fi network)
- **Same computer (Chrome / desktop):** `http://localhost:3000`

The address must be reachable from the device you use. On Windows, allow port
`3000` in the firewall if a physical device cannot connect.

The Android manifest already declares the permissions the app needs (internet,
microphone, camera, audio settings, network state, Bluetooth) and allows
cleartext HTTP traffic for local development.

## Tests and analysis

From the project root:

```bash
flutter test
flutter analyze
```

## Project structure

```text
.
├── android/                     Android configuration and native code
├── backend/                     Node.js server and SQLite database
│   ├── db.js                     Database schema and access
│   ├── package.json              npm dependencies and scripts
│   ├── package-lock.json         Locked npm dependencies
│   └── server.js                 REST API and Socket.IO events
├── lib/                          Flutter app
│   ├── main.dart                 Entry point
│   ├── utils.dart                Helpers
│   ├── models/
│   │   └── chat.dart             App state, models and server client
│   ├── screens/
│   │   ├── auth_screen.dart      Login and sign-up
│   │   ├── call_screen.dart      Audio and video calls (WebRTC)
│   │   ├── calls_people.dart     Call history and people list
│   │   ├── chat_screen.dart      Conversation
│   │   ├── home_screen.dart      Chat list and navigation
│   │   ├── media_screen.dart     Shared media, files and links
│   │   ├── new_chat_screen.dart  Find people and start a chat
│   │   ├── profile_screen.dart   Profile and settings
│   │   └── splash_screen.dart    Welcome screen
│   ├── theme/
│   │   └── colors.dart
│   └── widgets/
│       ├── attachments.dart      Voice player, image viewer, file row
│       └── common.dart           Avatar, logo and brand
├── test/
│   └── widget_test.dart          Flutter tests
├── web/                          Web platform files
├── windows/                      Windows platform files
├── analysis_options.yaml         Dart analysis rules
├── pubspec.yaml                  Flutter dependencies and configuration
├── pubspec.lock                  Resolved Flutter dependency versions
└── README.md
```

## API overview

REST endpoints (all `/api` routes except register and login require a
`Authorization: Bearer <token>` header):

| Method | Route | Description |
|---|---|---|
| GET | `/health` | Server status |
| POST | `/api/register` | Create an account |
| POST | `/api/login` | Log in |
| GET | `/api/me` | Current user |
| GET | `/api/users/search?q=` | Search users |
| GET | `/api/conversations` | List conversations |
| POST | `/api/conversations/direct` | Open or create a direct conversation |
| GET | `/api/conversations/:id/messages` | Conversation messages |
| DELETE | `/api/messages/:id` | Delete a message (`mode`: `me` or `everyone`) |
| POST | `/api/upload` | Upload a photo, file or voice message |
| POST | `/api/profile/photo` | Update the profile photo |
| GET | `/api/calls` | Call history |

Socket.IO events: `message:send`, `message:new`, `message:deleted`,
`message:hidden`, `typing`, `messages:read`, `presence`, `profile:updated`,
`call:offer`, `call:answer`, `call:ice`, `call:reject`, `call:end`.

## Known limitations

- Calls use public STUN servers only. Between two different networks, some calls
  may fail without a TURN relay.
- The other person must be online with the app open to receive a call or a
  message in real time (no push notifications).
- Only direct (one-to-one) conversations are available. Group chats and
  end-to-end encryption are not implemented.
- Files and the database are stored on the server disk.
