import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonora_flutter/player/sonora_audio_handler.dart';
import 'package:sonora_flutter/services/music_api.dart';
import 'package:sonora_flutter/ui/app_shell.dart';
import 'package:sonora_flutter/ui/sonora_theme.dart';

import 'support/fake_audio_player.dart';
import 'support/test_viewport.dart';

const _art = 'assets/art/neon-rain.png';

void main() {
  testWidgets('See all opens a page listing the whole section', (tester) async {
    useTestViewport(tester);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('See all'), findsNWidgets(4));
    expect(find.byTooltip('Back'), findsNothing);

    const sections = [
      (0, '1 playlist'),
      (1, '2 albums'),
      (2, '3 songs'),
      (3, '1 artist'),
    ];
    for (final (index, subtitle) in sections) {
      await tester.tap(find.text('See all').at(index));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.text(subtitle), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Back'), findsNothing);
    }
  });

  testWidgets('home hero shows a random catalog track and can shuffle', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    useTestViewport(tester);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final initialTitle = tester
        .widget<Text>(find.byKey(const ValueKey('hero-track-title')))
        .data;
    expect(_songs.map((track) => track.title), contains(initialTitle));
    expect(find.text('RANDOM PICK'), findsOneWidget);
    expect(find.byTooltip('Shuffle song'), findsOneWidget);

    await tester.tap(find.byTooltip('Shuffle song'));
    await tester.pump();

    final shuffledTitle = tester
        .widget<Text>(find.byKey(const ValueKey('hero-track-title')))
        .data;
    expect(shuffledTitle, isNot(initialTitle));
  });

  testWidgets('tapping a track queues the list it belongs to, so Next works', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    useTestViewport(tester);

    final player = FakeAudioPlayer();
    final handler = SonoraAudioHandler(player: player);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          catalogProvider.overrideWith((ref) async => _songs),
          playlistsProvider.overrideWith((ref) async => const []),
          albumsProvider.overrideWith((ref) async => const []),
          artistsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(theme: SonoraTheme.dark, home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    // Home's "Made for you" rail: the tapped track starts a queue of the whole
    // list, not a queue of one, so Next has somewhere to go.
    await tester.tap(
      find.descendant(
        of: find.byType(HomeView),
        matching: find.byWidgetPredicate(
          (widget) => widget is TrackTile && widget.track.id == 'song-1',
        ),
      ),
    );
    player.finishLoad();
    await tester.pumpAndSettle();

    expect(
      handler.queue.value.map((track) => track.id),
      _songs.map((track) => track.id),
    );

    // The tapped track is the one playing.
    expect(handler.mediaItem.value?.id, 'song-1');

    // Next walks that queue rather than stopping: song-1 is at index 1, so it
    // moves on to index 2.
    unawaited(handler.skipToNext());
    await tester.pump();
    player.finishLoad();
    await tester.pumpAndSettle();
    expect(handler.mediaItem.value?.id, 'song-2');
  });
}

Widget _app() {
  return ProviderScope(
    overrides: [
      audioHandlerProvider.overrideWithValue(SonoraAudioHandler()),
      catalogProvider.overrideWith((ref) async => _songs),
      playlistsProvider.overrideWith((ref) async => [_playlist]),
      albumsProvider.overrideWith((ref) async => _albums),
      artistsProvider.overrideWith((ref) async => [_artist]),
    ],
    child: MaterialApp(theme: SonoraTheme.dark, home: const AppShell()),
  );
}

final _songs = [
  for (var index = 0; index < 3; index++)
    MediaItem(
      id: 'song-$index',
      title: 'Song $index',
      artist: 'Sonora',
      album: 'Night drive',
      extras: {
        'art': _art,
        // A real url, so the handler actually loads and advances the track
        // rather than stopping at the missing source.
        'url': 'https://cdn.test/song-$index.mp3',
      },
    ),
];

final _playlist = _collection('pl-1', 'Night drive', CollectionKind.playlist);
final _albums = [
  _collection('al-1', 'After dark', CollectionKind.album),
  _collection('al-2', 'Soft focus', CollectionKind.album),
];
final _artist = _collection('ar-1', 'Arijit Singh', CollectionKind.artist);

MusicCollection _collection(String id, String name, CollectionKind kind) =>
    MusicCollection(
      id: id,
      name: name,
      imageUrl: _art,
      subtitle: switch (kind) {
        CollectionKind.album => 'Album',
        CollectionKind.artist => 'Artist',
        CollectionKind.playlist => 'Playlist',
      },
      kind: kind,
    );
