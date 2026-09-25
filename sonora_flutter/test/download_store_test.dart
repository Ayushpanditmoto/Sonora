import 'dart:async';

import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonora_flutter/services/download_store.dart';
import 'package:sonora_flutter/services/track_source.dart';
import 'package:sonora_flutter/services/youtube_api.dart';

import 'support/media_fixtures.dart';

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
  DownloadStore storeWith({
    DownloadFetcher? fetcher,
    ResolveTrackStream? resolveStream,
    SegmentedDownloadFetcher? segmentedFetcher,
  }) => DownloadStore(
    fetcher:
        fetcher ??
        (url, path, onProgress) async {
          final file = File(path)..writeAsBytesSync(mediaPayload(12));
          onProgress(7, 7);
          return file.lengthSync();
        },
    directory: () async => dir,
    resolveStream: resolveStream,
    segmentedFetcher: segmentedFetcher,
  );

  test('a download is kept, with its size, and survives a restart', () async {
    final store = storeWith();
    await store.load();

    await store.download(track('a', url: 'https://cdn.test/a.mp3'));

    expect(store.contains('a'), isTrue);
    expect(store.tracks.single.id, 'a');
    // The size reported by the fetch, which is what the card adds up.
    expect(store.totalBytes, 12);
    expect(File(store.localPathFor('a')!).existsSync(), isTrue);

    // Read back the way a new launch would.
    final reopened = storeWith();
    await reopened.load();

    expect(reopened.tracks.single.id, 'a');
    expect(reopened.localPathFor('a'), isNotNull);
  });

  test('the default fetcher writes a real HTTP response to disk', () async {
    final payload = mediaPayload(128 * 1024);
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

  for (final format in YouTubeAudioFormat.values) {
    test(
      'a YouTube download uses the resolved ${format.fileExtension}',
      () async {
        final seenUrls = <String>[];
        final item = MediaItem(
          id: 'youtube:video_1',
          title: 'Authorized audio',
          artist: 'Creator',
          extras: const {'source': 'youtube', 'sourceId': 'video_1'},
        );
        final store = storeWith(
          resolveStream: (track) async {
            expect(track.id, 'youtube:video_1');
            return ResolvedTrackSource(
              url: Uri.parse(
                'https://media.test/audio.${format.fileExtension}',
              ),
              extension: format.fileExtension,
            );
          },
          fetcher: (url, path, onProgress) async {
            seenUrls.add(url);
            final file = File(path)..writeAsBytesSync(mediaPayload(12));
            onProgress(file.lengthSync(), file.lengthSync());
            return file.lengthSync();
          },
        );
        await store.load();

        await store.download(item);

        final path = store.localPathFor(item.id)!;
        expect(store.contains(item.id), isTrue);
        expect(seenUrls, ['https://media.test/audio.${format.fileExtension}']);
        expect(path, endsWith('youtube_video_1.${format.fileExtension}'));
        expect(item.extras, isNot(contains('url')));

        final reopened = storeWith();
        await reopened.load();
        expect(reopened.tracks.single.extras, isNot(contains('url')));
        expect(reopened.localPathFor(item.id), path);
      },
    );
  }

  test('a 403 download retries with a freshly resolved YouTube URL', () async {
    var resolutions = 0;
    final seenUrls = <String>[];
    final freshPayload = mediaPayload(12);
    final item = MediaItem(
      id: 'youtube:retry_1',
      title: 'Retry audio',
      extras: const {'source': 'youtube', 'sourceId': 'retry_1'},
    );
    final store = storeWith(
      resolveStream: (track) async {
        resolutions++;
        return ResolvedTrackSource(
          url: Uri.parse('https://media.test/retry-$resolutions.m4a'),
          extension: 'm4a',
        );
      },
      fetcher: (url, path, onProgress) async {
        seenUrls.add(url);
        final file = File(path);
        if (resolutions == 1) {
          file.writeAsBytesSync(mediaPayload(12));
          final request = RequestOptions(path: url);
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.badResponse,
            response: Response<void>(requestOptions: request, statusCode: 403),
          );
        }
        file.writeAsBytesSync(freshPayload);
        onProgress(freshPayload.length, freshPayload.length);
        return file.lengthSync();
      },
    );
    await store.load();

    await store.download(item);

    expect(resolutions, 2);
    expect(seenUrls, [
      'https://media.test/retry-1.m4a',
      'https://media.test/retry-2.m4a',
    ]);
    expect(store.contains(item.id), isTrue, reason: store.errorFor(item.id));
    expect(File(store.localPathFor(item.id)!).readAsBytesSync(), freshPayload);
  });

  test('a known-length YouTube source uses the segmented downloader', () async {
    var regularCalls = 0;
    var segmentedCalls = 0;
    final item = MediaItem(
      id: 'youtube:segmented_1',
      title: 'Segmented audio',
      extras: const {'source': 'youtube', 'sourceId': 'segmented_1'},
    );
    final store = storeWith(
      fetcher: (url, path, onProgress) async {
        regularCalls++;
        return 0;
      },
      resolveStream: (track) async => ResolvedTrackSource(
        url: Uri(scheme: 'https', host: 'media.test', path: '/audio.m4a'),
        extension: 'm4a',
        contentLength: 2048,
      ),
      segmentedFetcher: (url, path, contentLength, onProgress) async {
        segmentedCalls++;
        expect(contentLength, 2048);
        final file = File(path)..writeAsBytesSync(mediaPayload(12));
        onProgress(7, contentLength);
        return file.lengthSync();
      },
    );
    await store.load();

    await store.download(item);

    expect(regularCalls, 0);
    expect(segmentedCalls, 1);
    expect(store.contains(item.id), isTrue);
  });

  test(
    'the segmented downloader assembles concurrent ranges in order',
    () async {
      final payload = mediaPayload(1024 * 1024 + 137);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final ranges = <String>[];
      server.listen((request) async {
        final value = request.headers.value('range');
        if (value == null) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          return;
        }
        ranges.add(value);
        final bounds = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(value)!;
        final start = int.parse(bounds.group(1)!);
        final end = int.parse(bounds.group(2)!);
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          'content-range',
          'bytes $start-$end/${payload.length}',
        );
        request.response.headers.contentLength = end - start + 1;
        request.response.add(payload.sublist(start, end + 1));
        await request.response.close();
      });

      final previousHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      try {
        final item = MediaItem(
          id: 'youtube:segmented_1',
          title: 'Segmented audio',
          extras: const {'source': 'youtube', 'sourceId': 'segmented_1'},
        );
        final store = DownloadStore(
          directory: () async => dir,
          resolveStream: (track) async => ResolvedTrackSource(
            url: Uri.parse('http://127.0.0.1:${server.port}/audio.m4a'),
            extension: 'm4a',
            contentLength: payload.length,
          ),
        );
        await store.load();

        await store.download(item);

        expect(
          store.contains(item.id),
          isTrue,
          reason: store.errorFor(item.id),
        );
        expect(ranges, hasLength(4));
        expect(File(store.localPathFor(item.id)!).readAsBytesSync(), payload);
      } finally {
        HttpOverrides.global = previousHttpOverrides;
      }
    },
  );

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

  test('a download that is not media is rejected instead of being stored', () async {
    // A response can arrive at full length while holding bytes from elsewhere
    // in the file. Storing it would leave a row that fails every time it is
    // played, so the download is reported as failed and stays retryable.
    final displaced = List<int>.filled(4096, 0x5a);
    final item = MediaItem(
      id: 'youtube:displaced_1',
      title: 'Displaced audio',
      extras: const {'source': 'youtube', 'sourceId': 'displaced_1'},
    );
    final store = storeWith(
      resolveStream: (track) async => ResolvedTrackSource(
        url: Uri.parse('https://media.test/audio.m4a'),
        extension: 'm4a',
      ),
      fetcher: (url, path, onProgress) async {
        final file = File(path)..writeAsBytesSync(displaced);
        onProgress(displaced.length, displaced.length);
        return file.lengthSync();
      },
    );
    await store.load();

    await store.download(item);

    expect(store.contains(item.id), isFalse);
    expect(store.errorFor(item.id), isNotNull);
    expect(store.localPathFor(item.id), isNull);
    expect(
      dir.listSync(),
      isEmpty,
      reason: 'the unusable file is not left on disk',
    );
  });

  test('a stored download that is no longer playable is dropped on load', () async {
    final store = storeWith();
    await store.load();
    await store.download(track('a', url: 'https://cdn.test/a.mp3'));
    final path = store.localPathFor('a')!;
    // The file exists and is the expected size, but it is not media.
    File(path).writeAsBytesSync(List<int>.filled(7, 0x5a));

    final reopened = storeWith();
    await reopened.load();

    expect(reopened.tracks, isEmpty);
    expect(
      File(path).existsSync(),
      isFalse,
      reason: 'the unplayable file is cleaned up rather than kept',
    );
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
        final file = File(path)..writeAsBytesSync(mediaPayload(12));
        return file.lengthSync();
      },
    );
    await store.load();

    await store.downloadAll([
      track('a', url: 'https://cdn.test/a.mp3'),
      track('b', url: 'https://cdn.test/b.mp3'),
    ]);

    expect(seen, ['https://cdn.test/a.mp3', 'https://cdn.test/b.mp3']);
    // The fetch order remains a then b, but the Downloads UI shows the newest
    // completed track first.
    expect(store.tracks.map((t) => t.id), ['b', 'a']);
  });

  test(
    'the newest download is first and stays first after reopening',
    () async {
      final store = storeWith();
      await store.load();

      await store.download(track('a', url: 'https://cdn.test/a.mp3'));
      await store.download(track('b', url: 'https://cdn.test/b.mp3'));

      expect(store.tracks.map((t) => t.id), ['b', 'a']);

      final reopened = storeWith();
      await reopened.load();
      expect(reopened.tracks.map((t) => t.id), ['b', 'a']);
    },
  );

  test('progress distinguishes known totals from unknown totals', () async {
    final knownStarted = Completer<void>();
    final releaseKnown = Completer<void>();
    final unknownStarted = Completer<void>();
    final releaseUnknown = Completer<void>();
    final store = storeWith(
      fetcher: (url, path, onProgress) async {
        final file = File(path)..writeAsBytesSync(mediaPayload(12));
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
        final file = File(path)..writeAsBytesSync(mediaPayload(12));
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

  test(
    'rapid progress chunks are coalesced into a bounded update burst',
    () async {
      var notifications = 0;
      final store = storeWith(
        fetcher: (url, path, onProgress) async {
          final file = File(path)..writeAsBytesSync(mediaPayload(12));
          for (var received = 1; received <= 200; received++) {
            onProgress(received, 200);
          }
          return file.lengthSync();
        },
      );
      await store.load();
      store.addListener(() => notifications++);

      await store.download(track('fast', url: 'https://cdn.test/fast.mp3'));

      expect(store.contains('fast'), isTrue);
      expect(
        notifications,
        lessThanOrEqualTo(3),
        reason: 'start, completion, and cleanup are the only needed updates',
      );
    },
  );

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
        final file = File(path)..writeAsBytesSync(mediaPayload(12));
        return file.lengthSync();
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
