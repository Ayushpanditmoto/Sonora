# 🎵 Sonora

Sonora is an open-source music streaming project with two clients:

- A responsive **Next.js web player** in the repository root.
- A cross-platform **Flutter mobile player** in [`sonora_flutter/`](./sonora_flutter/).

<p align="center">
  <img src="./public/screenshot.png" alt="Sonora web app screenshot" width="800"/>
</p>

## 📦 Android APK

Download the latest universal Android build from GitHub Releases:

**[⬇ Download the latest Sonora APK](https://github.com/Ayushpanditmoto/Sonora/releases/latest)**

The current release is [Sonora v1.0.4](https://github.com/Ayushpanditmoto/Sonora/releases/tag/v1.0.4). APK builds are open-source sideloading releases and use Flutter's automatic debug signing; no private keystore is stored in this repository. Android may ask you to allow installs from unknown sources. If Android reports a signing conflict when installing a newer build, uninstall the previous Sonora version first.

A SHA-256 checksum is published beside every APK:

- [Sonora-1.0.4+5.apk](https://github.com/Ayushpanditmoto/Sonora/releases/download/v1.0.4/Sonora-1.0.4%2B5.apk)
- [SHA-256 checksum](https://github.com/Ayushpanditmoto/Sonora/releases/download/v1.0.4/Sonora-1.0.4%2B5.apk.sha256)

> **Upgrading to v1.0.3:** music now loads from JioSaavn directly instead of through a third-party proxy that stopped working. Existing offline downloads cannot be matched to the new track identifiers, so they are cleared on first launch. Re-download anything you want to keep offline.

## ✨ Features

- Browse, search, and play music from JioSaavn
- Queue management with previous, next, seek, shuffle, and repeat controls
- Favorites, listening history, and local downloads
- Responsive web layout for desktop, tablet, and mobile
- Persistent mini-player and full-screen now-playing view
- Background audio, Android media notifications, and lock-screen controls in Flutter
- Original local album artwork for reliable rendering

## 🛠️ Tech stack

| Client | Stack |
| --- | --- |
| Web | Next.js, React, TypeScript, Tailwind CSS, Zustand |
| Mobile | Flutter, Dart, Riverpod, `go_router`, `just_audio`, `audio_service` |
| Media/data | Sonora/Saavn API integration with Dio |

## 🚀 Getting started

### Web app

Requirements: Node.js 18 or later and npm.

```bash
git clone https://github.com/Ayushpanditmoto/Sonora.git
cd Sonora
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) in your browser.

### Flutter app

Requirements: Flutter 3.47.2 or a compatible stable Flutter SDK.

```bash
git clone https://github.com/Ayushpanditmoto/Sonora.git
cd Sonora/sonora_flutter
flutter pub get
flutter run
```

For a browser preview of the Flutter client:

```bash
flutter run -d web-server --web-port=8082
```

## ✅ Validation

Run the Flutter checks from the mobile project directory:

```bash
cd sonora_flutter
flutter analyze
flutter test
```

## 📁 Project structure

```text
.
├── app/                    # Next.js App Router pages
├── components/             # Web UI components
├── hooks/                  # Web data and player hooks
├── lib/                    # Web utilities and providers
├── public/                 # Web assets
├── services/               # Web API services
├── store/                  # Web player state
├── sonora_flutter/         # Flutter mobile application
│   ├── android/            # Android host project
│   ├── assets/             # Local album artwork
│   ├── lib/                # Flutter application code
│   └── test/               # Flutter unit and widget tests
├── types/                  # Shared web TypeScript types
└── .github/workflows/      # Automated GitHub releases
```

## 📦 Maintainer releases

Android releases are automated by [`.github/workflows/android-release.yml`](./.github/workflows/android-release.yml). To publish a new version:

1. Update `version` in `sonora_flutter/pubspec.yaml` (for example, `1.0.1+2`).
2. Commit and push the version change.
3. Create and push the matching tag:

   ```bash
   git tag v1.0.1
   git push origin v1.0.1
   ```

The workflow validates the tag, runs Flutter analysis and tests, builds the universal APK, and attaches the APK and checksum to the GitHub Release.

## 🤝 Contributing

Contributions are welcome. Please keep changes focused, run the relevant validation commands, and open an issue or pull request describing your work.

## 🙏 Credits

- Sonora music API integration and streaming data
- [Flutter](https://flutter.dev/) and [Dart](https://dart.dev/)
- [Next.js](https://nextjs.org/) and [React](https://react.dev/)
- [Lucide](https://lucide.dev/) for interface icons

Made with ❤️ by [Ayush Pandit](https://github.com/ayushpanditmoto)
