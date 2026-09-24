# Sonora Mobile

A polished Flutter music player with original artwork, responsive navigation,
search, favorites, a persistent mini-player, and full background audio controls.

## Included

- Home, search, and library experiences
- Full-screen now-playing view
- Play, pause, seek, previous, and next controls
- Android media notification and iOS lock-screen audio setup
- Riverpod state and a reusable audio-service layer
- Local original album artwork for reliable rendering
- Live catalog, artwork, search, and streams from Sonora's Saavn API

## Run

```bash
flutter pub get
flutter run
```

The browser preview can be started with:

```bash
flutter run -d web-server --web-port=8082
```

## Music API

`lib/services/music_api.dart` uses the same `saavn.sumit.co` API as the Sonora
web app. It maps API songs into `MediaItem` objects used by the player, queue,
Android media notification, search, and artwork views.
