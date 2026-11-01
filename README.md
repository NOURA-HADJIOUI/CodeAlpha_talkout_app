# TalkOut

TalkOut est une application de messagerie développée avec Flutter. Elle permet
de discuter en temps réel, de partager des fichiers et de passer des appels
audio ou vidéo. Le projet comprend une application Flutter et un serveur Node.js
avec une base de données SQLite.

## Fonctionnalités

- Création de compte et connexion avec nom d'utilisateur et mot de passe.
- Recherche d'utilisateurs et conversations directes.
- Envoi et réception de messages en temps réel, avec indicateurs de présence,
  de saisie et de lecture.
- Compteur de messages non lus et compteur d'appels manqués non consultés.
- Partage de photos, de fichiers et de messages vocaux (25 Mo maximum par
  fichier).
- Appels audio et vidéo avec WebRTC.
- Ajout, remplacement et suppression de la photo de profil.
- Historique des appels.
- Consultation des médias, fichiers et liens partagés.
- Stockage des comptes et conversations dans SQLite.

## Technologies

- **Application :** Flutter et Dart
- **Temps réel et appels :** Socket.IO et WebRTC
- **Serveur :** Node.js, Express et Socket.IO
- **Base de données :** SQLite avec `better-sqlite3`

## Prérequis

- Flutter et Dart installés.
- Node.js et npm installés.
- Un émulateur, un appareil Android connecté ou une plateforme Flutter prise
  en charge.

## Installation et démarrage

### 1. Installer et démarrer le serveur

Dans un terminal, depuis le dossier `backend` :

```bash
npm install
npm start
```

Le serveur écoute sur le port `3000` par défaut. La base SQLite
(`backend/talkout.db`) et le dossier des fichiers partagés (`backend/uploads`)
sont créés ou utilisés par le serveur.

Pour définir le port ou la clé de signature des sessions, configurez les
variables d'environnement `PORT` et `JWT_SECRET` avant de démarrer le serveur.
En production, définissez toujours une clé `JWT_SECRET` privée et robuste.

### 2. Installer et démarrer l'application

Depuis la racine du projet :

```bash
flutter pub get
flutter run
```

Sur l'écran de connexion, développez **Server settings** et indiquez l'adresse
du serveur :

- **Émulateur Android :** `http://10.0.2.2:3000`
- **Appareil physique :** `http://<adresse-IP-du-PC>:3000` (les deux appareils
  doivent être sur le même réseau).
- **Ordinateur local :** `http://localhost:3000`

L'adresse doit être accessible depuis l'appareil utilisé.

## Tests et analyse

À la racine du projet, exécutez :

```bash
flutter test
flutter analyze
```

## Structure du projet

```text
.
├── android/                     Configuration et code natif Android
├── backend/                     Serveur Node.js et base SQLite
│   ├── db.js                     Accès à la base de données
│   ├── package.json              Dépendances et scripts npm
│   ├── package-lock.json         Verrouillage des dépendances npm
│   └── server.js                 API REST et événements Socket.IO
├── lib/                          Application Flutter
│   ├── main.dart                 Point d'entrée
│   ├── utils.dart                Utilitaires
│   ├── models/
│   │   └── chat.dart             Modèle de conversation
│   ├── screens/
│   │   ├── auth_screen.dart
│   │   ├── call_screen.dart
│   │   ├── calls_people.dart
│   │   ├── chat_screen.dart
│   │   ├── home_screen.dart
│   │   ├── media_screen.dart
│   │   ├── new_chat_screen.dart
│   │   ├── profile_screen.dart
│   │   └── splash_screen.dart
│   ├── theme/
│   │   └── colors.dart
│   └── widgets/
│       ├── attachments.dart
│       └── common.dart
├── test/
│   └── widget_test.dart          Tests Flutter
├── web/                          Fichiers de la plateforme Web
├── windows/                      Fichiers de la plateforme Windows
├── analysis_options.yaml         Règles d'analyse Dart
├── pubspec.yaml                  Dépendances et configuration Flutter
├── pubspec.lock                  Versions résolues des dépendances Flutter
└── README.md
```
