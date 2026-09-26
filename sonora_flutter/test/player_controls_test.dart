import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonora_flutter/player/sonora_audio_handler.dart';
import 'package:sonora_flutter/player/system_volume.dart';
import 'package:sonora_flutter/services/music_api.dart';
import 'package:sonora_flutter/services/track_source.dart';
import 'package:sonora_flutter/ui/app_shell.dart';
import 'package:sonora_flutter/ui/components/artwork.dart';
import 'package:sonora_flutter/ui/sonora_theme.dart';

import 'support/fake_audio_player.dart';
import 'support/test_viewport.dart';

const _art = 'assets/art/neon-rain.png';

void main() {
  testWidgets('the loading spinner does not move the progress bar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    useTestViewport(tester);
    final source = Completer<ResolvedTrackSource>();
    final player = FakeAudioPlayer();
    final handler = SonoraAudioHandler(
      player: player,
      resolveStream: (track) => source.future,
    );
    final track = MediaItem(
      id: 'youtube:loading_1',
      title: 'Loading song',
      artist: 'YouTube',
      duration: const Duration(minutes: 3),
      extras: const {'source': 'youtube', 'sourceId': 'loading_1'},
    );
    final loading = handler.playTrack(track);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          positionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
          catalogProvider.overrideWith((ref) async => _songs),
          playlistsProvider.overrideWith((ref) async => const []),
          albumsProvider.overrideWith((ref) async => const []),
          artistsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(theme: SonoraTheme.dark, home: const AppShell()),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(MiniPlayer));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final nowPlaying = find.byType(NowPlayingView);
    expect(nowPlaying, findsOneWidget);
    expect(find.text('Loading audio…'), findsNothing);
    expect(
      find.descendant(
        of: nowPlaying,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: nowPlaying,
        matching: find.byTooltip('Preparing track'),
      ),
      findsOneWidget,
    );
    final progress = find.descendant(
      of: nowPlaying,
      matching: find.byType(Slider),
    );
    final slider = tester.widget<Slider>(progress);
    expect(slider.onChanged, isNull);
    final loadingProgressRect = tester.getRect(progress);
    expect(player.stopCount, 1);
    expect(player.loadedUrls, isEmpty);

    source.complete(
      ResolvedTrackSource(
        url: Uri.parse('https://media.test/loading.m4a'),
        extension: 'm4a',
      ),
    );
    await tester.pump();
    player.finishLoad();
    await loading;
    await tester.pumpAndSettle();

    expect(tester.getRect(progress), loadingProgressRect);
    // Routine rebuffering must not disable seeking or introduce any vertical
    // layout shift; only resolving a replacement source locks the slider.
    handler.playbackState.add(
      PlaybackState(processingState: AudioProcessingState.buffering),
    );
    await tester.pump();
    expect(tester.widget<Slider>(progress).onChanged, isNotNull);
    expect(find.text('Loading audio…'), findsNothing);
    expect(tester.getRect(progress), loadingProgressRect);
    expect(player.loadedUrls, ['https://media.test/loading.m4a']);
  });

  testWidgets('shuffle, repeat and the queue work from the player', (
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
          // The real one ticks off the audio service, which is not running here.
          positionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
          catalogProvider.overrideWith((ref) async => _songs),
          playlistsProvider.overrideWith((ref) async => const []),
          albumsProvider.overrideWith((ref) async => const []),
          artistsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(theme: SonoraTheme.dark, home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    // The shell keeps every tab alive, so target the Home tab's track row
    // rather than the hero title, which may show the same song.
    await tester.tap(
      find.descendant(
        of: find.byType(HomeView),
        matching: find.byWidgetPredicate(
          (widget) => widget is TrackTile && widget.track.id == '1',
        ),
      ),
    );
    player.finishLoad();
    await tester.pumpAndSettle();

    expect(handler.mediaItem.value?.id, '1');

    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();

    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(find.text('3 in queue'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NowPlayingView),
        matching: find.text('42 plays'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('track-plays-1')),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.descendant(
        of: find.byType(TrackTile),
        matching: find.byTooltip('Favorite'),
      ),
      findsNothing,
    );
    expect(find.byTooltip('Save track'), findsNothing);
    expect(find.byTooltip('Favorite'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NowPlayingView),
        matching: find.byTooltip('Download'),
      ),
      findsOneWidget,
      reason: 'every playable track exposes download beside Like',
    );

    // Shuffle turns on and leaves the playing track at the front.
    await tester.tap(find.byTooltip('Shuffle off'));
    await tester.pumpAndSettle();

    expect(
      handler.playbackState.value.shuffleMode,
      AudioServiceShuffleMode.all,
    );
    expect(find.byTooltip('Shuffle on'), findsOneWidget);
    expect(handler.queue.value.first.id, '1');
    expect(handler.queue.value.map((track) => track.id).toSet(), {
      '1',
      '2',
      '3',
    });

    // Repeat cycles off -> all -> one -> off, and one loops the player.
    await tester.tap(find.byTooltip('Repeat off'));
    await tester.pumpAndSettle();
    expect(handler.playbackState.value.repeatMode, AudioServiceRepeatMode.all);

    await tester.tap(find.byTooltip('Repeat all'));
    await tester.pumpAndSettle();
    expect(handler.playbackState.value.repeatMode, AudioServiceRepeatMode.one);
    expect(player.loopMode, LoopMode.one);

    await tester.tap(find.byTooltip('Repeat one'));
    await tester.pumpAndSettle();
    expect(handler.playbackState.value.repeatMode, AudioServiceRepeatMode.none);
    expect(player.loopMode, LoopMode.off);

    // The queue sheet lists the queue and can jump straight to a track.
    await tester.tap(find.byTooltip('Up next'));
    await tester.pumpAndSettle();

    expect(find.text('3 tracks in the queue'), findsOneWidget);
    // The track that is playing is the highlighted row in the sheet.
    final playingTitle = tester.widget<Text>(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Song 1'),
        matching: find.text('Song 1'),
      ),
    );
    expect(playingTitle.style?.color, SonoraColors.green);

    // The queue rows are the only list tiles titled "Song 3".
    await tester.tap(find.widgetWithText(ListTile, 'Song 3'));
    player.finishLoad();
    await tester.pumpAndSettle();

    expect(handler.mediaItem.value?.id, '3');
  });

  /// Drags a finger across [target] with a small vertical wobble, the way a
  /// real thumb moves, and returns once the finger is lifted. [steps] is how
  /// many little moves the travel is split into, so the default touch slop and
  /// the gesture arena are exercised exactly as they are on a device.
  Future<void> flingOver(
    WidgetTester tester,
    Finder target, {
    required double dx,
  }) async {
    final start = tester.getCenter(target);
    final gesture = await tester.startGesture(start);
    const step = Duration(milliseconds: 16);
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(
        Offset(dx / 12, i.isEven ? 3 : -2), // The wobble a real finger has.
      );
      await tester.pump(step);
    }
    await gesture.up();
    await tester.pump();
  }

  testWidgets('swiping sideways on the player changes the volume', (
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
          positionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
          catalogProvider.overrideWith((ref) async => _songs),
          playlistsProvider.overrideWith((ref) async => const []),
          // No device volume here, so the swipe exercises the player gain
          // fallback synchronously; the device path is covered in
          // system_volume_test.dart.
          systemVolumeProvider.overrideWithValue(
            FakeSystemVolume(writesWork: false),
          ),

          albumsProvider.overrideWith((ref) async => const []),
          artistsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(theme: SonoraTheme.dark, home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(HomeView),
        matching: find.byWidgetPredicate(
          (widget) => widget is TrackTile && widget.track.id == '1',
        ),
      ),
    );
    player.finishLoad();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(NowPlayingView)),
    );
    expect(container.read(volumeProvider), 1);

    // Sliding right raises the volume, left lowers it. A real finger is used
    // throughout, because the earlier version of this test disabled the touch
    // slop and that is what hid the gesture never firing on a device.
    await flingOver(tester, find.byType(NowPlayingView), dx: -210);
    expect(container.read(volumeProvider), lessThan(1));
    // The level reached the player, not just the UI.
    expect(player.volumes.last, container.read(volumeProvider));

    await flingOver(tester, find.byType(NowPlayingView), dx: 210);
    expect(container.read(volumeProvider), 1);
    expect(find.text('100%'), findsWidgets);

    // A slide is relative to where the finger went down, not to the whole
    // range, so a small drag lands between the two ends.
    await flingOver(tester, find.byType(NowPlayingView), dx: -90);
    final partial = container.read(volumeProvider);
    expect(partial, inExclusiveRange(0.5, 1.0));

    // Repeated slides drive it all the way down; the level clamps at silent
    // rather than going below zero.
    for (var i = 0; i < 3; i++) {
      await flingOver(tester, find.byType(NowPlayingView), dx: -400);
    }
    expect(container.read(volumeProvider), 0);
    expect(player.volumes.last, 0);
    expect(find.text('0%'), findsWidgets);

    // Sliding right again brings the volume back rather than getting stuck
    // silent. The sheet is 640 wide (Material 3 caps a bottom sheet), so the
    // full range is 70% of that; a longer drag saturates at full.
    await flingOver(tester, find.byType(NowPlayingView), dx: 620);
    expect(container.read(volumeProvider), 1);

    // Sliding on the artwork works too, which is where a real thumb naturally
    // lands. The artwork used to swallow the gesture entirely. The finder is
    // scoped to the player, because the mini player underneath has artwork too.
    final art = find.descendant(
      of: find.byType(NowPlayingView),
      matching: find.byType(Artwork),
    );
    await flingOver(tester, find.byType(NowPlayingView), dx: -560);
    expect(container.read(volumeProvider), 0);
    await flingOver(tester, art, dx: 560);
    expect(container.read(volumeProvider), 1);
    expect(player.volumes.last, 1);

    // The seek bar keeps its own job: sliding on it seeks, it does not move the
    // volume. It is checked from the middle of the range, because a slide at
    // full volume is clamped and would hide a volume change that still happened.
    container.read(volumeProvider.notifier).set(0.5);
    await tester.pump();
    final applied = player.volumes.length;
    final seekBar = find.descendant(
      of: find.byType(NowPlayingView),
      matching: find.byType(Slider),
    );
    await flingOver(tester, seekBar, dx: 120);
    expect(container.read(volumeProvider), 0.5);
    expect(player.volumes.length, applied);
    expect(player.seeks, isNotEmpty);
  });

  testWidgets('the artwork swipe survives the sheet being draggable', (
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
          positionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
          catalogProvider.overrideWith((ref) async => _songs),
          playlistsProvider.overrideWith((ref) async => const []),
          albumsProvider.overrideWith((ref) async => const []),
          artistsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(theme: SonoraTheme.dark, home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(HomeView),
        matching: find.byWidgetPredicate(
          (widget) => widget is TrackTile && widget.track.id == '1',
        ),
      ),
    );
    player.finishLoad();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();

    // The player is a draggable bottom sheet, so its own vertical drag
    // recogniser competes for every touch. The swipe works anyway because it
    // reads raw pointer events instead of entering the gesture arena. This
    // guards that: swapping it back for a GestureDetector fails here.
    expect(find.byType(NowPlayingView), findsOneWidget);
    final art = find.descendant(
      of: find.byType(NowPlayingView),
      matching: find.byType(Artwork),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NowPlayingView)),
    );
    await flingOver(tester, art, dx: -300);
    expect(container.read(volumeProvider), lessThan(1));
  });

  testWidgets('a slide is ignored when it is not clearly sideways', (
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
          positionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
          catalogProvider.overrideWith((ref) async => _songs),
          playlistsProvider.overrideWith((ref) async => const []),
          albumsProvider.overrideWith((ref) async => const []),
          artistsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(theme: SonoraTheme.dark, home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(HomeView),
        matching: find.byWidgetPredicate(
          (widget) => widget is TrackTile && widget.track.id == '1',
        ),
      ),
    );
    player.finishLoad();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(NowPlayingView)),
    );

    // A tap and a mostly-vertical drag must not touch the volume: the player
    // still needs those for the buttons and for the sheet's own movement.
    final art = find.descendant(
      of: find.byType(NowPlayingView),
      matching: find.byType(Artwork),
    );
    await tester.tap(art, warnIfMissed: false);
    await tester.pump();
    expect(container.read(volumeProvider), 1);

    // Start from the middle of the range, otherwise the check below cannot fail:
    // at full volume a nudge to the right is clamped away and any bug that
    // reacts to it stays invisible.
    container.read(volumeProvider.notifier).set(0.5);
    await tester.pump();
    final applied = player.volumes.length;

    final gesture = await tester.startGesture(tester.getCenter(art));
    for (var i = 0; i < 10; i++) {
      // Mostly vertical, but drifting sideways the way a finger does.
      await gesture.moveBy(const Offset(2, 14));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();

    expect(container.read(volumeProvider), 0.5);
    expect(player.volumes.length, applied);
  });

  testWidgets('a slide still works when the finger drifts down first', (
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
          positionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
          catalogProvider.overrideWith((ref) async => _songs),
          playlistsProvider.overrideWith((ref) async => const []),
          // No device volume here, so the fallback to the player gain runs
          // synchronously; the device path is covered in system_volume_test.dart.
          systemVolumeProvider.overrideWithValue(
            FakeSystemVolume(writesWork: false),
          ),

          albumsProvider.overrideWith((ref) async => const []),
          artistsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(theme: SonoraTheme.dark, home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(HomeView),
        matching: find.byWidgetPredicate(
          (widget) => widget is TrackTile && widget.track.id == '1',
        ),
      ),
    );
    player.finishLoad();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(NowPlayingView)),
    );

    // A thumb does not travel in a straight line. This one drops noticeably
    // before it moves sideways, which is the shape that used to hand the
    // gesture to the sheet's vertical drag and leave the volume untouched.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(NowPlayingView)),
    );
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(0, 9));
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-14, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();

    expect(
      container.read(volumeProvider),
      lessThan(1),
      reason:
          'the volume should follow a slide that starts with vertical drift',
    );
    expect(player.volumes, isNotEmpty);
  });

  testWidgets('dragging the sheet down still closes the player', (
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
          positionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
          catalogProvider.overrideWith((ref) async => _songs),
          playlistsProvider.overrideWith((ref) async => const []),
          albumsProvider.overrideWith((ref) async => const []),
          artistsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(theme: SonoraTheme.dark, home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(HomeView),
        matching: find.byWidgetPredicate(
          (widget) => widget is TrackTile && widget.track.id == '1',
        ),
      ),
    );
    player.finishLoad();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingView), findsOneWidget);

    // The volume listener reads raw pointer events, so it must not swallow the
    // sheet's own drag. Pulling the player down has to dismiss it, and must not
    // change the volume on the way.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NowPlayingView)),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(NowPlayingView)),
    );
    // A bottom sheet only dismisses once it is pulled down past a fraction of
    // its own height, so this has to travel much further than a volume slide
    // does. The player is 3200 tall here, so 1760 is well past that line.
    for (var i = 0; i < 80; i++) {
      await gesture.moveBy(const Offset(0, 22));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(NowPlayingView), findsNothing);
    expect(container.read(volumeProvider), 1);
  });
}

final _songs = [
  _song('1', 'Song 1'),
  _song('2', 'Song 2'),
  _song('3', 'Song 3'),
];

MediaItem _song(String id, String title) => MediaItem(
  id: id,
  title: title,
  artist: 'Sonora',
  extras: {'url': 'https://cdn.test/$id.mp3', 'art': _art, 'playCount': 42},
);
