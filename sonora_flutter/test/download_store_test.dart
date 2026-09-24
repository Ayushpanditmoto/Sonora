import 'dart:async';

import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonora_flutter/services/download_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('sonora_downloads');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  MediaItem track(String id, {String? url}) => MediaItem(
    id: id,
    title: 'Track $id',
    artist: 'Sonora',
    extras: {'url': ?url},
  );

  /// Writes a file the way a real download would, so the store's file handling
  /// is exercised rather than mocked away.
  DownloadStore storeWith({DownloadFetcher? fetcher}) => DownloadStore(
    fetcher:
        fetcher ??
        (url, path, onProgress) async {
          final file = File(path)..writeAsStringSync('audio:$url');
          onProgress(7, 7);
          return file.lengthSync();
        },
    directory: () async => dir,
  );

  test('a download is kept, with its size, and survives a restart', () async {
    final store = storeWith();
    await store.load();

    await store.download(track('a', url: 'https://cdn.test/a.mp3'));

    expect(store.contains('a'), isTrue);
    expect(store.tracks.single.id, 'a');
    // The size reported by the fetch, which is what the card adds up.
    expect(store.totalBytes, 'audio:https://cdn.test/a.mp3'.length);
    expect(File(store.localPathFor('a')!).existsSync(), isTrue);

    // Read back the way a new launch would.
    final reopened = storeWith();
    await reopened.load();

    expect(reopened.tracks.single.id, 'a');
    expect(reopened.localPathFor('a'), isNotNull);
  });

  test('the default fetcher writes a real HTTP response to disk', () async {
    final payload = List<int>.generate(128 * 1024, (index) => index % 251);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType('audio', 'mp3');
      request.response.headers.contentLength = payload.length;
      request.response.add(payload);
      await request.response.close();
    });

    final previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    try {
      final store = DownloadStore(directory: () async => dir);
      await store.load();
      await store.download(
        track('network', url: 'http://127.0.0.1:${server.port}/track.mp3'),
      );

      expect(
        store.contains('network'),
        isTrue,
        reason: store.errorFor('network'),
      );
      expect(store.totalBytes, payload.length);
      expect(File(store.localPathFor('network')!).readAsBytesSync(), payload);
    } finally {
      HttpOverrides.global = previousHttpOverrides;
    }
  });

  test('removing a download deletes the file', () async {
    final store = storeWith();
    await store.load();
    await store.download(track('a', url: 'https://cdn.test/a.mp3'));
    final path = store.localPathFor('a')!;

    await store.remove('a');

    expect(store.contains('a'), isFalse);
    expect(File(path).existsSync(), isFalse);
    expect(store.localPathFor('a'), isNull);
  });

  test('a stored download whose file has gone is dropped on load', () async {
    final store = storeWith();
    await store.load();
    await store.download(track('a', url: 'https://cdn.test/a.mp3'));
    File(store.localPathFor('a')!).deleteSync();

    final reopened = storeWith();
    await reopened.load();

    // Offering a track whose audio is gone would fail at playback time, so it
    // is not offered at all.
    expect(reopened.tracks, isEmpty);
  });

  test(
    'a failed download is reported on the track and leaves no file',
    () async {
      final store = storeWith(
        fetcher: (url, path, onProgress) async => throw StateError('offline'),
      );
      await store.load();

      await store.download(track('a', url: 'https://cdn.test/a.mp3'));

      expect(store.errorFor('a'), isNotNull);
      expect(store.contains('a'), isFalse);
      expect(dir.listSync(), isEmpty, reason: 'the partial file is cleaned up');
    },
  );

  test('a track with no audio is not downloaded', () async {
    final store = storeWith();
    await store.load();

    await store.download(track('a'));

    expect(store.contains('a'), isFalse);
    expect(store.errorFor('a'), contains('no audio'));
  });

  test('downloadAll fetches every track in order', () async {
    final seen = <String>[];
    final store = storeWith(
      fetcher: (url, path, onProgress) async {
        seen.add(url);
        return 4;
      },
    );
    await store.load();

    await store.downloadAll([
      track('a', url: 'https://cdn.test/a.mp3'),
      track('b', url: 'https://cdn.test/b.mp3'),
    ]);

    expect(seen, ['https://cdn.test/a.mp3', 'https://cdn.test/b.mp3']);
    expect(store.tracks.map((t) => t.id), ['a', 'b']);
  });

  test('progress distinguishes known totals from unknown totals', () async {
    final knownStarted = Completer<void>();
    final releaseKnown = Completer<void>();
    final unknownStarted = Completer<void>();
    final releaseUnknown = Completer<void>();
    final store = storeWith(
      fetcher: (url, path, onProgress) async {
        final file = File(path)..writeAsStringSync('audio');
        if (url.endsWith('/known.mp3')) {
          onProgress(2, 4);
          knownStarted.complete();
          await releaseKnown.future;
          onProgress(4, 4);
        } else {
          onProgress(3, -1);
          unknownStarted.complete();
          await releaseUnknown.future;
        }
        return file.lengthSync();
      },
    );
    await store.load();

    final known = store.download(
      track('known', url: 'https://cdn.test/known.mp3'),
    );
    await knownStarted.future;
    expect(store.progressFor('known'), 0.5);
    expect(store.isProgressIndeterminate('known'), isFalse);
    expect(store.activeDownloadCount, 1);
    expect(store.activeBytes, 2);

    releaseKnown.complete();
    await known;
    expect(store.progressFor('known'), isNull);
    expect(store.activeDownloadCount, 0);
    expect(store.activeBytes, 0);

    final unknown = store.download(
      track('unknown', url: 'https://cdn.test/unknown.mp3'),
    );
    await unknownStarted.future;
    expect(store.progressFor('unknown'), 0);
    expect(store.isProgressIndeterminate('unknown'), isTrue);
    expect(store.activeDownloadCount, 1);
    expect(store.activeBytes, 3);

    releaseUnknown.complete();
    await unknown;
    expect(store.progressFor('unknown'), isNull);
    expect(store.isProgressIndeterminate('unknown'), isFalse);
    expect(store.activeDownloadCount, 0);
    expect(store.activeBytes, 0);
  });

  test('retrying a failed download clears its error', () async {
    var attempts = 0;
    final store = storeWith(
      fetcher: (url, path, onProgress) async {
        attempts++;
        if (attempts == 1) throw StateError('offline');
        final file = File(path)..writeAsStringSync('audio');
        onProgress(file.lengthSync(), file.lengthSync());
        return file.lengthSync();
      },
    );
    await store.load();
    final item = track('a', url: 'https://cdn.test/a.mp3');

    await store.download(item);
    expect(store.errorFor('a'), isNotNull);
    expect(store.activeDownloadCount, 0);

    await store.download(item);
    expect(attempts, 2);
    expect(store.errorFor('a'), isNull);
    expect(store.contains('a'), isTrue);
  });

  test('only one collection batch can run at a time', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final seen = <String>[];
    final store = storeWith(
      fetcher: (url, path, onProgress) async {
        seen.add(url);
        if (url.endsWith('/a.mp3')) {
          firstStarted.complete();
          await releaseFirst.future;
        }
        return 4;
      },
    );
    await store.load();
    final firstBatch = store.downloadAll([
      track('a', url: 'https://cdn.test/a.mp3'),
      track('b', url: 'https://cdn.test/b.mp3'),
    ]);
    await firstStarted.future;

    expect(store.isBatchRunning, isTrue);
    expect(store.batchPosition, 1);
    expect(store.batchTotal, 2);
    expect(store.isBatchRunningFor(['a', 'b']), isTrue);
    expect(store.isBatchRunningFor(['c']), isFalse);

    await store.downloadAll([track('c', url: 'https://cdn.test/c.mp3')]);
    expect(seen, ['https://cdn.test/a.mp3']);
    expect(store.contains('c'), isFalse);

    releaseFirst.complete();
    await firstBatch;
    expect(seen, ['https://cdn.test/a.mp3', 'https://cdn.test/b.mp3']);
    expect(store.isBatchRunning, isFalse);
    expect(store.batchPosition, isNull);
    expect(store.batchTotal, isNull);
  });
}
