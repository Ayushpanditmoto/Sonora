import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sonora_flutter/player/media_item_codec.dart';
import 'package:sonora_flutter/player/sonora_audio_handler.dart';
import 'package:sonora_flutter/services/track_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_audio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The handler remembers the last session, so local storage has to answer here.
  SharedPreferences.setMockInitialValues({});

  test('a superseded load is swallowed and the newest track wins', () async {
    final player = FakeAudioPlayer();
    final handler = SonoraAudioHandler(player: player);

    final first = handler.playTrack(_track('a', 'https://cdn.test/a.mp3'));
    await _settle();
    expect(player.loadedUrls, ['https://cdn.test/a.mp3']);

    // Starting the second load aborts the first one, which is what makes
    // just_audio report `PlayerInterruptedException (Loading interrupted)`.
    final second = handler.playTrack(_track('b', 'https://cdn.test/b.mp3'));
    player.finishLoad();
    await _settle();

    await expectLater(first, completes);
    await expectLater(second, completes);
    expect(handler.mediaItem.value?.id, 'b');
    expect(player.loadedUrls, [
      'https://cdn.test/a.mp3',
      'https://cdn.test/b.mp3',
    ]);
    expect(player.playCount, 1, reason: 'only the newest load starts playback');
  });

  test(
    'the selected track and replacement queue are applied together',
    () async {
      final player = FakeAudioPlayer();
      final handler = SonoraAudioHandler(player: player);
      final tracks = [
        _track('a', 'https://cdn.test/a.mp3'),
        _track('b', 'https://cdn.test/b.mp3'),
        _track('c', 'https://cdn.test/c.mp3'),
      ];

      final playing = handler.playTrack(tracks[1], queue: tracks);

      expect(handler.mediaItem.value?.id, 'b');
      expect(handler.queue.value.map((track) => track.id), ['a', 'b', 'c']);
      expect(handler.playbackState.value.queueIndex, 1);
      player.finishLoad();
      await playing;
      expect(player.playCount, 1);
    },
  );

  test('play during a new load never resumes the previous source', () async {
    final player = FakeAudioPlayer();
    final handler = SonoraAudioHandler(player: player);
    final first = handler.playTrack(_track('a', 'https://cdn.test/a.mp3'));
    player.finishLoad();
    await first;
    expect(player.playCount, 1);

    final second = handler.playTrack(_track('b', 'https://cdn.test/b.mp3'));
    await _settle();
    // Simulates a play command arriving from the notification while B is still
    // loading and the player object can still report A's old source.
    await handler.play();
    await _settle();
    expect(player.loadedUrls, [
      'https://cdn.test/a.mp3',
      'https://cdn.test/b.mp3',
    ]);

    player.finishLoad();
    await second;
    expect(handler.mediaItem.value?.id, 'b');
    expect(player.playCount, 2, reason: 'A must not be played again behind B');
  });

  test(
    'switching stops the old source and publishes loading while resolving',
    () async {
      final source = Completer<ResolvedTrackSource>();
      final player = FakeAudioPlayer();
      final handler = SonoraAudioHandler(
        player: player,
        resolveStream: (track) => source.future,
      );
      final first = _track('a', 'https://cdn.test/a.mp3');
      final second = MediaItem(
        id: 'youtube:b',
        title: 'Second',
        extras: const {'source': 'youtube', 'sourceId': 'b'},
      );
      final playing = handler.playTrack(first);
      player.finishLoad();
      await playing;
      expect(player.playing, isTrue);

      final switching = handler.playTrack(second, queue: [first, second]);
      await _settle();

      expect(player.stopCount, 2, reason: 'initial stop plus track switch');
      expect(player.playing, isFalse);
      expect(player.audioSource, isNull);
      expect(handler.mediaItem.value?.id, 'youtube:b');
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.loading,
      );
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.updatePosition, Duration.zero);
      expect(player.loadedUrls, ['https://cdn.test/a.mp3']);

      source.complete(
        ResolvedTrackSource(
          url: Uri(scheme: 'https', host: 'media.test', path: '/b.m4a'),
          extension: 'm4a',
        ),
      );
      await _settle();
      expect(player.loadedUrls, [
        'https://cdn.test/a.mp3',
        'https://media.test/b.m4a',
      ]);
      player.finishLoad();
      await switching;

      expect(
        handler.playbackState.value.processingState,
        isNot(AudioProcessingState.loading),
      );
      expect(handler.playbackState.value.playing, isTrue);
      expect(player.playCount, 2);
    },
  );

  test('a failed replacement never resumes the old source', () async {
    final player = FakeAudioPlayer();
    final handler = SonoraAudioHandler(
      player: player,
      resolveStream: (track) async =>
          throw const TrackSourceResolutionException(' unavailable '),
    );
    final first = _track('a', 'https://cdn.test/a.mp3');
    final second = MediaItem(
      id: 'youtube:b',
      title: 'Second',
      extras: const {'source': 'youtube', 'sourceId': 'b'},
    );
    final playing = handler.playTrack(first);
    player.finishLoad();
    await playing;
    final message = handler.errors.first;

    await handler.playTrack(second, queue: [first, second]);

    expect(await message, ' unavailable ');
    expect(player.stopCount, 2);
    expect(player.playing, isFalse);
    expect(player.audioSource, isNull);
    expect(player.playCount, 1, reason: 'the old song must not resume');
    expect(handler.mediaItem.value?.id, 'youtube:b');
    expect(
      handler.playbackState.value.processingState,
      isNot(AudioProcessingState.loading),
    );
  });

  test(
    'a completion during a selected load cannot skip to another track',
    () async {
      final player = FakeAudioPlayer();
      final handler = SonoraAudioHandler(player: player);
      final tracks = [
        _track('a', 'https://cdn.test/a.mp3'),
        _track('b', 'https://cdn.test/b.mp3'),
        _track('c', 'https://cdn.test/c.mp3'),
      ];
      final first = handler.playTrack(tracks[0]);
      player.finishLoad();
      await first;

      final selected = handler.playTrack(tracks[1], queue: tracks);
      await _settle();
      player.emitProcessingState(ProcessingState.completed);
      await _settle();

      expect(player.loadedUrls, [
        'https://cdn.test/a.mp3',
        'https://cdn.test/b.mp3',
      ]);
      expect(handler.mediaItem.value?.id, 'b');

      player.finishLoad();
      await selected;
    },
  );

  test('tracks without a stream url are ignored', () async {
    final player = FakeAudioPlayer();
    final handler = SonoraAudioHandler(player: player);

    await handler.playTrack(MediaItem(id: 'a', title: 'A'));

    expect(player.loadedUrls, isEmpty);
    expect(handler.mediaItem.value, isNull);
  });

  test(
    'a YouTube track resolves a fresh URL only when playback starts',
    () async {
      final player = FakeAudioPlayer();
      var resolutions = 0;
      final handler = SonoraAudioHandler(
        player: player,
        resolveStream: (track) async {
          resolutions++;
          expect(track.id, 'youtube:video_1');
          return ResolvedTrackSource(
            url: Uri.parse('https://media.test/fresh-$resolutions.m4a'),
            extension: 'm4a',
            headers: const {'User-Agent': 'validated-media-client'},
          );
        },
      );
      final track = MediaItem(
        id: 'youtube:video_1',
        title: 'Authorized audio',
        extras: const {'source': 'youtube', 'sourceId': 'video_1'},
      );
      expect(resolutions, 0);

      final loading = handler.playTrack(track);
      await _settle();
      expect(resolutions, 1);
      expect(player.loadedUrls, ['https://media.test/fresh-1.m4a']);
      expect(player.loadedHeaders.last, {
        'User-Agent': 'validated-media-client',
      });
      expect(track.extras, isNot(contains('url')));

      player.finishLoad();
      await loading;
      expect(player.playCount, 1);

      await handler.stop();
      final reloading = handler.playTrack(track);
      await _settle();
      expect(
        resolutions,
        2,
        reason: 'a later load must not reuse an expired URL',
      );
      expect(player.loadedUrls, [
        'https://media.test/fresh-1.m4a',
        'https://media.test/fresh-2.m4a',
      ]);
      expect(player.loadedHeaders, [
        {'User-Agent': 'validated-media-client'},
        {'User-Agent': 'validated-media-client'},
      ]);
      player.finishLoad();
      await reloading;
    },
  );

  test('a forbidden YouTube URL is retried once with a fresh URL', () async {
    final player = FakeAudioPlayer()
      ..failOnceUrls.add('https://media.test/stale.m4a');
    var resolutions = 0;
    final handler = SonoraAudioHandler(
      player: player,
      resolveStream: (track) async {
        resolutions++;
        return ResolvedTrackSource(
          url: Uri.parse(
            resolutions == 1
                ? 'https://media.test/stale.m4a'
                : 'https://media.test/fresh.m4a',
          ),
          extension: 'm4a',
        );
      },
    );
    final track = MediaItem(
      id: 'youtube:video_1',
      title: 'Authorized audio',
      extras: const {'source': 'youtube', 'sourceId': 'video_1'},
    );

    final loading = handler.playTrack(track);
    await _settle();

    expect(resolutions, 2);
    expect(player.loadedUrls, [
      'https://media.test/stale.m4a',
      'https://media.test/fresh.m4a',
    ]);
    player.finishLoad();
    await loading;
    expect(handler.mediaItem.value?.id, track.id);
    expect(player.playCount, 1);
  });

  test(
    'starting playback does not keep the load active until song end',
    () async {
      final playCompleter = Completer<void>();
      final player = FakeAudioPlayer()..playCompleter = playCompleter;
      final handler = SonoraAudioHandler(player: player);
      final track = _track('a', 'https://cdn.test/a.mp3');

      final loading = handler.playTrack(track);
      player.finishLoad();

      await expectLater(loading, completes);
      expect(handler.mediaItem.value?.id, 'a');
      expect(player.playCount, 1);
      playCompleter.complete();
    },
  );

  test('replaying the loaded track restarts it without a new load', () async {
    final player = FakeAudioPlayer();
    final handler = SonoraAudioHandler(player: player);
    final track = _track('a', 'https://cdn.test/a.mp3');

    final load = handler.playTrack(track);
    player.finishLoad();
    await load;
    expect(player.playCount, 1);

    await handler.playTrack(track);

    expect(player.loadedUrls, ['https://cdn.test/a.mp3']);
    expect(player.seeks, [Duration.zero]);
    expect(player.playCount, 2);
  });

  test('a new queue keeps the playing track in place', () async {
    final player = FakeAudioPlayer();
    final handler = SonoraAudioHandler(player: player);

    final playing = handler.playTrack(_track('b', 'https://cdn.test/b.mp3'));
    player.finishLoad();
    await playing;

    await handler.loadQueue([
      _track('a', 'https://cdn.test/a.mp3'),
      _track('b', 'https://cdn.test/b.mp3'),
      _track('c', 'https://cdn.test/c.mp3'),
    ]);

    expect(handler.mediaItem.value?.id, 'b');
    expect(handler.playbackState.value.queueIndex, 1);

    // Next carries on from the track that is playing, not from the old index.
    final next = handler.skipToNext();
    await _settle();
    expect(handler.mediaItem.value?.id, 'c');
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.loading,
    );
    expect(player.stopCount, 2);
    expect(player.playing, isFalse);
    expect(player.audioSource, isNull);
    expect(player.loadedUrls, [
      'https://cdn.test/b.mp3',
      'https://cdn.test/c.mp3',
    ]);
    player.finishLoad();
    await next;
  });

  test('repeat all wraps the queue and repeat one loops the track', () async {
    final player = FakeAudioPlayer();
    final handler = SonoraAudioHandler(player: player);
    await handler.loadQueue([
      _track('a', 'https://cdn.test/a.mp3'),
      _track('b', 'https://cdn.test/b.mp3'),
    ]);

    final last = handler.playTrack(_track('b', 'https://cdn.test/b.mp3'));
    player.finishLoad();
    await last;
    expect(handler.playbackState.value.queueIndex, 1);

    // Without repeat the queue simply stops at the last track.
    await handler.skipToNext();
    expect(handler.mediaItem.value?.id, 'b');

    await handler.setRepeatMode(AudioServiceRepeatMode.all);
    final wrapped = handler.skipToNext();
    player.finishLoad();
    await wrapped;
    expect(handler.mediaItem.value?.id, 'a');
    expect(handler.playbackState.value.queueIndex, 0);

    await handler.setRepeatMode(AudioServiceRepeatMode.one);
    expect(player.loopMode, LoopMode.one);

    await handler.setRepeatMode(AudioServiceRepeatMode.none);
    expect(player.loopMode, LoopMode.off);
  });

  test(
    'shuffle randomises the rest of the queue but not the current track',
    () async {
      final player = FakeAudioPlayer();
      final handler = SonoraAudioHandler(player: player);
      await handler.loadQueue([
        _track('a', 'https://cdn.test/a.mp3'),
        _track('b', 'https://cdn.test/b.mp3'),
        _track('c', 'https://cdn.test/c.mp3'),
      ]);

      final playing = handler.playTrack(_track('b', 'https://cdn.test/b.mp3'));
      player.finishLoad();
      await playing;

      await handler.setShuffleMode(AudioServiceShuffleMode.all);

      final shuffled = handler.queue.value;
      expect(shuffled.first.id, 'b');
      expect(shuffled.map((track) => track.id).toSet(), {'a', 'b', 'c'});

      await handler.setShuffleMode(AudioServiceShuffleMode.none);
      expect(
        handler.playbackState.value.shuffleMode,
        AudioServiceShuffleMode.none,
      );
    },
  );

  test('the last session is remembered and comes back after a restart', () async {
    final first = SonoraAudioHandler(player: FakeAudioPlayer());
    await first.loadQueue([
      _track('a', 'https://cdn.test/a.mp3'),
      _track('b', 'https://cdn.test/b.mp3'),
    ]);
    final playing = first.playTrack(_track('b', 'https://cdn.test/b.mp3'));
    (first.player as FakeAudioPlayer).finishLoad();
    await playing;
    await _settle();

    // A fresh handler is what the next launch gets, so it has to find the
    // session on its own and come back paused on the same song.
    final relaunched = SonoraAudioHandler(player: FakeAudioPlayer());
    await relaunched.restoreLastSession();
    final restored = relaunched.player as FakeAudioPlayer;

    expect(relaunched.mediaItem.value?.id, 'b');
    expect(relaunched.queue.value.map((track) => track.id), ['a', 'b']);
    // The index has to point at the song too, or next would walk from the top.
    expect(relaunched.playbackState.value.queueIndex, 1);
    // Restored state only: nothing is loaded and nothing plays on its own.
    expect(relaunched.player.playing, isFalse);
    expect(restored.loadedUrls, isEmpty);
  });

  test('a session that cannot be stored does not break playback', () async {
    // Storage is unavailable, as it is in a test without local storage.
    final player = FakeAudioPlayer();
    final handler = SonoraAudioHandler(player: player);
    final playing = handler.playTrack(_track('a', 'https://cdn.test/a.mp3'));
    player.finishLoad();

    await expectLater(playing, completes);
    expect(handler.mediaItem.value?.id, 'a');
    expect(player.playCount, 1);
  });

  test(
    'a playback failure is reported instead of escaping as an exception',
    () async {
      final player = FakeAudioPlayer()..failLoadsWith = 10000000;
      final handler = SonoraAudioHandler(player: player);

      // Listen before starting playback: the error is published while the load
      // fails, and a broadcast stream does not replay it to a later subscriber.
      final message = handler.errors.first;
      // The UI starts playback without awaiting it, so a real failure has to be
      // turned into something the screen can show.
      await expectLater(
        handler.playTrack(_track('a', 'https://cdn.test/a.mp3')),
        completes,
      );

      expect(await message, isNotEmpty);
    },
  );

  test('a stored session that is not readable is ignored', () async {
    SharedPreferences.setMockInitialValues({
      'sonora.last_session': 'not json at all',
    });
    final handler = SonoraAudioHandler(player: FakeAudioPlayer());

    await expectLater(handler.restoreLastSession(), completes);
    expect(handler.mediaItem.value, isNull);
  });

  test('a session with no usable track is ignored', () async {
    SharedPreferences.setMockInitialValues({
      'sonora.last_session': encodeLastSession(
        current: _track('a', 'https://cdn.test/a.mp3'),
        queue: const [],
      ),
    });
    final handler = SonoraAudioHandler(player: FakeAudioPlayer());

    await expectLater(handler.restoreLastSession(), completes);
    expect(handler.mediaItem.value, isNull);
  });
}

MediaItem _track(String id, String url) =>
    MediaItem(id: id, title: id, extras: {'url': url});

Future<void> _settle() async {
  for (var turn = 0; turn < 5; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}
