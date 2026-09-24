import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonora_flutter/services/music_api.dart';
import 'package:sonora_flutter/ui/app_shell.dart';
import 'package:sonora_flutter/ui/sonora_theme.dart';

const _art = 'assets/art/neon-rain.png';

void main() {
  testWidgets('empty search invites a query without showing mood browsing', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Search Sonora'), findsOneWidget);
    expect(
      find.text('Search for songs, albums, artists, and playlists'),
      findsOneWidget,
    );
    expect(find.text('Browse moods'), findsNothing);
    expect(find.text('Popular searches'), findsNothing);
  });

  testWidgets('search groups songs, albums, artists, and playlists', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Arijit');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Search Song'), findsOneWidget);
    expect(find.text('Search Album'), findsOneWidget);
    expect(find.text('Search Artist'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Playlists'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('Search Playlist'), findsOneWidget);
  });
}

Widget _app() {
  return ProviderScope(
    overrides: [
      searchResultsProvider.overrideWith((ref, query) async => _songs),
      searchCollectionsProvider.overrideWith(
        (ref, key) async => switch (key.kind) {
          CollectionKind.album => [_album],
          CollectionKind.artist => [_artist],
          CollectionKind.playlist => [_playlist],
        },
      ),
    ],
    child: MaterialApp(
      theme: SonoraTheme.dark,
      home: const Scaffold(body: SearchView()),
    ),
  );
}

final _songs = [
  MediaItem(
    id: 'song-1',
    title: 'Search Song',
    artist: 'Arijit Singh',
    extras: {'art': _art, 'url': 'https://cdn.test/song.mp3'},
  ),
];

final _album = _collection('album-1', 'Search Album', CollectionKind.album);
final _artist = _collection('artist-1', 'Search Artist', CollectionKind.artist);
final _playlist = _collection(
  'playlist-1',
  'Search Playlist',
  CollectionKind.playlist,
);

MusicCollection _collection(String id, String name, CollectionKind kind) {
  return MusicCollection(
    id: id,
    name: name,
    imageUrl: _art,
    subtitle: kind.name,
    kind: kind,
  );
}
