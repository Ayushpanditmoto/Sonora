import 'dart:async';

import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonora_flutter/player/sonora_audio_handler.dart';
import 'package:sonora_flutter/services/download_store.dart';
import 'package:sonora_flutter/services/music_api.dart';
import 'package:sonora_flutter/ui/app_shell.dart';
import 'package:sonora_flutter/ui/sonora_theme.dart';

import 'support/fake_audio_player.dart';
import 'support/test_viewport.dart';

const _art = 'assets/art/neon-rain.png';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a downloaded track is played from its file, not the network', (
    tester,
  ) async {
    useTestViewport(tester);
    SharedPreferences.setMockInitialValues({});
    // Synchronous, because a widget test runs on a fake clock: a real async
    // file operation started here would never finish.
    final dir = Directory.systemTemp.createTempSync('sonora_downloads_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    final downloads = DownloadStore(
      // No real bytes are written: what is being checked is which source the
      // player asks for, not that the file has content.
      fetcher: (url, path, onProgress) async {
        onProgress(10, 10);
        return 10;
      },
      directory: () async => dir,
    );
    await downloads.load();

    final player = FakeAudioPlayer();
    // The player asks the same store the UI writes to, which is how main wires
    // the two together.
    final handler = SonoraAudioHandler(
      player: player,
      localPathFor: downloads.localPathFor,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          downloadStoreProvider.overrideWithValue(downloads),
          catalogProvider.overrideWith((ref) async => _catalog),
          playlistsProvider.overrideWith((ref) async => const []),
          albumsProvider.overrideWith((ref) async => [_album]),
          artistsProvider.overrideWith((ref) async => const []),
          collectionTracksProvider.overrideWith(
            (ref, key) async => _albumSongs,
          ),
        ],
        child: MaterialApp(theme: SonoraTheme.dark, home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Midnight Static'));
    await tester.pumpAndSettle();

    // Downloading the first song, from the row itself. A download writes to the
    // real filesystem, which only runs on the real event loop, so the tap is
    // followed by runAsync and then a single frame. The row shows a spinner
    // while it works, so the frame cannot be settled either.
    await tester.tap(find.byTooltip('Download').first);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(downloads.contains('1'), isTrue);
    expect(find.byTooltip('Remove download'), findsWidgets);

    await tester.tap(find.text('Album song 1'));
    await tester.pumpAndSettle();

    // Played from the file on the device, so the network is never asked for it.
    expect(player.loadedPaths, [downloads.localPathFor('1')]);
    expect(player.loadedUrls, isEmpty);

    // A track that was not downloaded still streams as before.
    await tester.tap(find.text('Album song 2'));
    await tester.pumpAndSettle();

    expect(player.loadedUrls, ['https://cdn.test/2.mp3']);
  });

  testWidgets('track rows show progress and keep failed downloads retryable', (
    tester,
  ) async {
    useTestViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync(
      'sonora_download_feedback_test',
    );
    addTearDown(() => dir.deleteSync(recursive: true));

    final releaseFailure = Completer<void>();
    final releaseUnknown = Completer<void>();
    var firstAttempts = 0;
    final downloads = DownloadStore(
      fetcher: (url, path, onProgress) async {
        if (url.endsWith('/1.mp3')) {
          firstAttempts++;
          if (firstAttempts == 1) {
            onProgress(5, 10);
            await releaseFailure.future;
            throw StateError('offline');
          }
          final file = File(path)..writeAsStringSync('audio');
          onProgress(file.lengthSync(), file.lengthSync());
          return file.lengthSync();
        }
        onProgress(2048, -1);
        await releaseUnknown.future;
        final file = File(path)..writeAsStringSync('audio');
        return file.lengthSync();
      },
      directory: () async => dir,
    );
    await downloads.load();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(
            SonoraAudioHandler(player: FakeAudioPlayer()),
          ),
          downloadStoreProvider.overrideWithValue(downloads),
          catalogProvider.overrideWith((ref) async => _catalog),
          playlistsProvider.overrideWith((ref) async => const []),
          albumsProvider.overrideWith((ref) async => [_album]),
          artistsProvider.overrideWith((ref) async => const []),
          collectionTracksProvider.overrideWith(
            (ref, key) async => _albumSongs,
          ),
        ],
        child: MaterialApp(theme: SonoraTheme.dark, home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Midnight Static'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Download').first);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    final knownProgress = tester.widget<CircularProgressIndicator>(
      find.descendant(
        of: find.byTooltip('Downloading 50%'),
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    expect(knownProgress.value, 0.5);

    releaseFailure.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.text('Download failed. Try again.'), findsOneWidget);
    expect(find.byTooltip('Retry download'), findsOneWidget);

    await tester.tap(find.byTooltip('Retry download'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.text('Download failed. Try again.'), findsNothing);
    expect(find.byTooltip('Remove download'), findsOneWidget);

    // Removing a completed download asks first, so a tap cannot delete it by
    // accident.
    await tester.tap(find.byTooltip('Remove download'));
    await tester.pumpAndSettle();
    expect(find.text('Remove download?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove download'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove download'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove download'), findsNothing);

    await tester.tap(find.byTooltip('Download').last);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    final unknownProgress = tester.widget<CircularProgressIndicator>(
      find.descendant(
        of: find.byTooltip('Downloading'),
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    expect(unknownProgress.value, isNull);

    releaseUnknown.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.byTooltip('Remove download'), findsOneWidget);
  });

  testWidgets('a batch and the library downloads tab report active state', (
    tester,
  ) async {
    useTestViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync(
      'sonora_download_batch_ui_test',
    );
    addTearDown(() => dir.deleteSync(recursive: true));

    final releaseFirst = Completer<void>();
    final downloads = DownloadStore(
      fetcher: (url, path, onProgress) async {
        if (url.endsWith('/1.mp3')) {
          onProgress(2048, 4096);
          await releaseFirst.future;
        }
        final file = File(path)..writeAsStringSync('audio');
        return file.lengthSync();
      },
      directory: () async => dir,
    );
    await downloads.load();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(
            SonoraAudioHandler(player: FakeAudioPlayer()),
          ),
          downloadStoreProvider.overrideWithValue(downloads),
          catalogProvider.overrideWith((ref) async => _catalog),
          playlistsProvider.overrideWith((ref) async => const []),
          albumsProvider.overrideWith((ref) async => [_album]),
          artistsProvider.overrideWith((ref) async => const []),
          collectionTracksProvider.overrideWith(
            (ref, key) async => _albumSongs,
          ),
        ],
        child: MaterialApp(theme: SonoraTheme.dark, home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Midnight Static'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Download all'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.text('1 of 2 • 2 left'), findsOneWidget);
    final batchButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '1 of 2 • 2 left'),
    );
    expect(batchButton.onPressed, isNull);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Library'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(
      find.text('Downloads'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('1 download • 2 KB received'), findsOneWidget);

    releaseFirst.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.text('1 download • 2 KB received'), findsNothing);
    expect(find.textContaining('2 tracks'), findsWidgets);
  });

  testWidgets('the downloads tab lists what is on the device', (tester) async {
    useTestViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('sonora_downloads_page');
    addTearDown(() => dir.deleteSync(recursive: true));

    final downloads = DownloadStore(
      fetcher: (url, path, onProgress) async {
        File(path).writeAsStringSync('audio');
        return 5;
      },
      directory: () async => dir,
    );
    await downloads.load();
    // Downloaded before the first frame so the page opens on a real entry.
    await tester.runAsync(() => downloads.download(_albumSongs.first));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(
            SonoraAudioHandler(player: FakeAudioPlayer()),
          ),
          downloadStoreProvider.overrideWithValue(downloads),
          catalogProvider.overrideWith((ref) async => const []),
          playlistsProvider.overrideWith((ref) async => const []),
          albumsProvider.overrideWith((ref) async => const []),
          artistsProvider.overrideWith((ref) async => const []),
        ],
        // Wrapped in a Scaffold because the library's cards are ink surfaces,
        // which need a Material ancestor; the app supplies one via AppShell.
        child: MaterialApp(
          theme: SonoraTheme.dark,
          home: const Scaffold(body: LibraryView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The card sits below the liked-songs block, so the sliver has not built it
    // until the library is scrolled.
    await tester.scrollUntilVisible(
      find.text('Downloads'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    // The downloads tab reports what is there.
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.textContaining('1 track'), findsWidgets);

    await tester.tap(find.text('Downloads'));
    await tester.pumpAndSettle();

    expect(find.text('Album song 1'), findsOneWidget);
    expect(find.text('Play all'), findsOneWidget);

    // Clearing asks first, so the audio is not deleted by a stray tap.
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Remove all downloads?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(downloads.tracks, hasLength(1));

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove all'));
    await tester.pumpAndSettle();

    expect(downloads.tracks, isEmpty);
  });

  testWidgets('tapping a collection lists its songs and plays them in order', (
    tester,
  ) async {
    useTestViewport(tester);

    final player = FakeAudioPlayer();
    final handler = SonoraAudioHandler(player: player);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          catalogProvider.overrideWith((ref) async => _catalog),
          playlistsProvider.overrideWith((ref) async => const []),
          albumsProvider.overrideWith((ref) async => [_album]),
          artistsProvider.overrideWith((ref) async => const []),
          collectionTracksProvider.overrideWith(
            (ref, key) async => _albumSongs,
          ),
        ],
        child: MaterialApp(theme: SonoraTheme.dark, home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Midnight Static'));
    await tester.pumpAndSettle();

    expect(find.text('ALBUM'), findsOneWidget);
    expect(find.text('2 songs'), findsOneWidget);
    expect(find.text('Album song 1'), findsOneWidget);
    expect(find.text('Album song 2'), findsOneWidget);

    await tester.tap(find.text('Play all'));
    await tester.pumpAndSettle();

    expect(player.loadedUrls, ['https://cdn.test/1.mp3']);
    expect(handler.queue.value.map((track) => track.id), ['1', '2']);
    expect(handler.mediaItem.value?.id, '1');

    // Playing a later song keeps the album as the queue.
    await tester.tap(find.text('Album song 2'));
    await tester.pumpAndSettle();

    expect(player.loadedUrls, [
      'https://cdn.test/1.mp3',
      'https://cdn.test/2.mp3',
    ]);
    expect(handler.mediaItem.value?.id, '2');

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // Back on home: the collection page is gone (its tracks now also show up
    // in "Recently played").
    expect(find.text('ALBUM'), findsNothing);
    expect(find.text('Play all'), findsNothing);
  });
}

final _catalog = [_song('c1', 'Catalog song 1'), _song('c2', 'Catalog song 2')];

final _albumSongs = [_song('1', 'Album song 1'), _song('2', 'Album song 2')];

final _album = MusicCollection(
  id: 'al-1',
  name: 'Midnight Static',
  imageUrl: _art,
  subtitle: 'Album',
  kind: CollectionKind.album,
);

MediaItem _song(String id, String title) => MediaItem(
  id: id,
  title: title,
  artist: 'Sonora',
  album: 'Midnight Static',
  extras: {'url': 'https://cdn.test/$id.mp3', 'art': _art},
);
