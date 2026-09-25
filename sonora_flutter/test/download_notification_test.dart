import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonora_flutter/services/download_notification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.panditfx.sonora/downloads');
  final calls = <MethodCall>[];
  TargetPlatform? previousPlatform;

  setUp(() {
    calls.clear();
    previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = previousPlatform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'download notification reports ordered progress and completion',
    () async {
      final notifier = DownloadNotifier();
      final track = MediaItem(
        id: 'track-1',
        title: 'Midnight Static',
        artist: 'Sonora',
      );

      final start = notifier.start(track, batchPosition: 1, batchTotal: 3);
      final update = notifier.update(
        track,
        receivedBytes: 512,
        totalBytes: 1024,
        batchPosition: 1,
        batchTotal: 3,
      );
      await Future.wait([start, update]);
      await notifier.complete(track, batchPosition: 1, batchTotal: 3);
      await notifier.clear();

      expect(calls.map((call) => call.method), [
        'requestPermission',
        'start',
        'update',
        'complete',
        'clear',
      ]);
      expect(
        (calls[1].arguments as Map)['title'],
        'Downloading Midnight Static',
      );
      expect(
        (calls[2].arguments as Map)['text'],
        'Track 1 of 3 • 50% • 512 B of 1 KB',
      );
      expect((calls[2].arguments as Map)['progress'], 50);
      expect((calls[3].arguments as Map)['text'], 'Track 1 of 3');
    },
  );
}
