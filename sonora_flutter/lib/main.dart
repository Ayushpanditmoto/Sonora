import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'player/sonora_audio_handler.dart';
import 'services/download_store.dart';
import 'sonora_app.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Color(0xFF090B0A),
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Read before the handler is built, because the handler asks this store where
  // a track's audio is: a downloaded track is played from its own file instead
  // of the network, so the list has to be in hand before the first load.
  final downloads = DownloadStore();
  await downloads.load();

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  final handler = await AudioService.init<SonoraAudioHandler>(
    builder: () => SonoraAudioHandler(localPathFor: downloads.localPathFor),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.ayushpandit.sonora.audio',
      androidNotificationChannelName: 'Sonora playback',
      androidStopForegroundOnPause: false,
    ),
  );
  // Restored before the first frame so the mini player and the player open on
  // the song that was playing last time rather than empty.
  await handler.restoreLastSession();
  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        // The same store the handler reads, so a track downloaded now is the one
        // the next load plays from its file.
        downloadStoreProvider.overrideWithValue(downloads),
      ],
      child: const SonoraApp(),
    ),
  );
}
