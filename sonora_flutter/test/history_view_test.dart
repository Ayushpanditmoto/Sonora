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

void main() {
  testWidgets('played tracks are kept in a local history and can be cleared', (
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
          catalogProvider.overrideWith((ref) async => _catalog),
          playlistsProvider.overrideWith((ref) async => const []),
          albumsProvider.overrideWith((ref) async => const []),
          artistsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(theme: SonoraTheme.dark, home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    // Nothing is in the history before anything is played.
    expect(find.text('Recently played'), findsNothing);

    // Home lists the tracks in both the "Made for you" grid and the rail.
    // Target the row itself because the random hero can show the same title.
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is TrackTile && widget.track.id == 'c1',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is TrackTile && widget.track.id == 'c2',
      ),
    );
    await tester.pumpAndSettle();

    // Home shows the latest play, newest first.
    expect(find.text('Recently played'), findsOneWidget);

    // The "See all" action on home opens the full history. It is the first of
    // the section headers, because "Recently played" sits highest on the page.
    await tester.tap(find.text('See all').first);
    await tester.pumpAndSettle();

    expect(find.text('History'), findsOneWidget);
    expect(find.text('2 tracks played'), findsOneWidget);
    expect(find.text('Play history'), findsOneWidget);
    expect(find.text('Catalog song 1'), findsOneWidget);
    // The newest track is the one playing, so it is also shown in the mini
    // player pinned under the page.
    expect(find.text('Catalog song 2'), findsNWidgets(2));

    // Playing the history makes it the queue and starts at the newest track.
    await tester.tap(find.text('Play history'));
    await tester.pumpAndSettle();

    expect(handler.queue.value.map((track) => track.id), ['c2', 'c1']);
    expect(handler.mediaItem.value?.id, 'c2');

    // The library card leads to the same page.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.library_music_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recently played'));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsOneWidget);

    // Swiping one row away drops just that song from the history.
    await tester.drag(
      find.text('Catalog song 1'),
      const Offset(-500, 0),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('Catalog song 1'), findsNothing);
    expect(find.text('1 track played'), findsOneWidget);

    // Clearing asks first, then empties the history.
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Clear history?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Songs you play will show up here.'), findsOneWidget);
    expect(find.text('Play history'), findsNothing);
    expect(find.text('Catalog song 1'), findsNothing);
  });

  test('history is restored on the next launch, newest first', () async {
    SharedPreferences.setMockInitialValues({});

    final first = RecentStore();
    await first.load();
    first.add(_catalog[0]);
    first.add(_catalog[1]);
    first.add(_catalog[0]); // Replaying a song moves it back to the front.
    // Saves are fire and forget, so give the write a chance to land.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final restored = RecentStore();
    await restored.load();
    expect(restored.tracks.map((track) => track.id), ['c1', 'c2']);

    // A store that is already open sees later plays without reloading.
    restored.add(_catalog[1]);
    expect(restored.tracks.map((track) => track.id), ['c2', 'c1']);
  });

  test('history keeps the 50 most recent tracks', () async {
    SharedPreferences.setMockInitialValues({});
    final store = RecentStore();
    await store.load();

    for (var i = 0; i < 60; i++) {
      store.add(
        MediaItem(
          id: 't$i',
          title: 'Track $i',
          extras: {'url': 'https://cdn.test/$i.mp3'},
        ),
      );
    }
    expect(store.tracks.length, 50);
    // The oldest ones fall off the end.
    expect(store.tracks.first.id, 't59');
    expect(store.tracks.last.id, 't10');

    await Future<void>.delayed(const Duration(milliseconds: 50));
    final restored = RecentStore();
    await restored.load();
    expect(restored.tracks.length, 50);
  });
}

final _catalog = [
  MediaItem(
    id: 'c1',
    title: 'Catalog song 1',
    artist: 'Sonora',
    extras: {'url': 'https://cdn.test/c1.mp3'},
  ),
  MediaItem(
    id: 'c2',
    title: 'Catalog song 2',
    artist: 'Sonora',
    extras: {'url': 'https://cdn.test/c2.mp3'},
  ),
];
