import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonora_flutter/services/music_api.dart';
import 'package:sonora_flutter/services/youtube_api.dart';
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
    expect(tester.widget<Text>(find.text('Search Sonora')).style?.fontSize, 26);
    expect(find.text('Search songs and YouTube'), findsOneWidget);
    expect(find.text('Browse moods'), findsNothing);
    expect(find.text('Popular searches'), findsNothing);
  });

  testWidgets('YouTube is the second Search tab', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Arijit');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final tabs = tester
        .widgetList<Tab>(find.byType(Tab))
        .map((tab) => tab.text)
        .toList();
    expect(tabs, ['Songs', 'YouTube', 'Albums', 'Artists', 'Playlists']);
    expect(find.text('Search Song'), findsOneWidget);
    expect(find.text('YouTube Track'), findsNothing);

    await tester.tap(find.widgetWithText(Tab, 'YouTube'));
    await tester.pumpAndSettle();
    expect(find.text('YouTube Track'), findsOneWidget);
    expect(find.text('Search Song'), findsNothing);
    expect(
      find.text('Download only videos you own or have permission to save.'),
      findsOneWidget,
    );
  });

  testWidgets('only the selected Search tab is requested', (tester) async {
    var songRequests = 0;
    var youtubeRequests = 0;
    final collectionRequests = <CollectionKind>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          youtubeSearchAvailableProvider.overrideWithValue(true),
          searchResultsProvider.overrideWith((ref, query) async {
            songRequests++;
            return _songs;
          }),
          youtubeSearchResultsProvider.overrideWith((ref, query) async {
            youtubeRequests++;
            return _youtube;
          }),
          searchCollectionsProvider.overrideWith((ref, key) async {
            collectionRequests.add(key.kind);
            return [_album];
          }),
        ],
        child: MaterialApp(
          theme: SonoraTheme.dark,
          home: const Scaffold(body: SearchView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Arijit');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(songRequests, 1);
    expect(youtubeRequests, 0);
    expect(collectionRequests, isEmpty);

    await tester.tap(find.widgetWithText(Tab, 'YouTube'));
    await tester.pumpAndSettle();
    expect(youtubeRequests, 1);
    expect(songRequests, 1);
    expect(collectionRequests, isEmpty);

    await tester.tap(find.widgetWithText(Tab, 'Albums'));
    await tester.pumpAndSettle();
    expect(collectionRequests, [CollectionKind.album]);
    expect(songRequests, 1);
    expect(youtubeRequests, 1);
  });

  testWidgets(
    'leaving Search releases focus and returning does not reopen it',
    (tester) async {
      var searchActive = true;
      late StateSetter updateSearch;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [youtubeSearchAvailableProvider.overrideWithValue(true)],
          child: MaterialApp(
            theme: SonoraTheme.dark,
            home: StatefulBuilder(
              builder: (context, setState) {
                updateSearch = setState;
                return Scaffold(
                  body: IndexedStack(
                    index: searchActive ? 1 : 0,
                    children: [
                      const SizedBox.expand(),
                      SearchView(isActive: searchActive),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.pump();
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);

      updateSearch(() => searchActive = false);
      await tester.pump();
      expect(field.focusNode.hasFocus, isFalse);

      updateSearch(() => searchActive = true);
      await tester.pump();
      expect(field.focusNode.hasFocus, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('YouTube results are hidden when the feature is unavailable', (
    tester,
  ) async {
    var youtubeRequests = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          youtubeSearchAvailableProvider.overrideWithValue(false),
          searchResultsProvider.overrideWith((ref, query) async => _songs),
          youtubeSearchResultsProvider.overrideWith((ref, query) async {
            youtubeRequests++;
            return _youtube;
          }),
        ],
        child: MaterialApp(
          theme: SonoraTheme.dark,
          home: const Scaffold(body: SearchView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Search songs and YouTube'), findsNothing);
    expect(find.text('Search songs'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Arijit');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byType(Tab), findsWidgets);
    expect(find.widgetWithText(Tab, 'YouTube'), findsNothing);
    expect(youtubeRequests, 0);
    expect(find.text('YouTube Track'), findsNothing);
    expect(find.text('Search Song'), findsOneWidget);
  });
}

Widget _app() {
  return ProviderScope(
    overrides: [
      youtubeSearchAvailableProvider.overrideWithValue(true),
      searchResultsProvider.overrideWith((ref, query) async => _songs),
      youtubeSearchResultsProvider.overrideWith((ref, query) async => _youtube),
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

final _album = MusicCollection(
  id: 'album-1',
  name: 'Search Album',
  imageUrl: _art,
  subtitle: 'Album',
  kind: CollectionKind.album,
);

final _youtube = [
  MediaItem(
    id: 'youtube:video_1',
    title: 'YouTube Track',
    artist: 'Creator',
    album: 'YouTube',
    extras: const {'source': 'youtube', 'sourceId': 'video_1'},
  ),
];
