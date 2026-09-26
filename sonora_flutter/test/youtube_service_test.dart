import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonora_flutter/services/track_source.dart';
import 'package:sonora_flutter/services/youtube_api.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('YouTube results use source-aware metadata without a temporary URL', () {
    final item = youtubeMediaItem(
      const YouTubeVideo(
        id: 'video_1',
        title: 'Authorized audio',
        author: 'Creator',
        pageUrl: 'https://www.youtube.com/watch?v=video_1',
        artworkUrl: 'https://img.youtube.com/vi/video_1/hqdefault.jpg',
        duration: Duration(minutes: 3),
      ),
    );

    expect(item.id, 'youtube:video_1');
    expect(item.artist, 'Creator');
    expect(item.album, 'YouTube');
    expect(item.artUri, isNotNull);
    expect(item.extras?['source'], youtubeSource);
    expect(item.extras?['sourceId'], 'video_1');
    expect(item.extras?['pageUrl'], contains('video_1'));
    expect(item.extras, isNot(contains('url')));
  });

  test('M4A is preferred over a higher-bitrate WebM stream', () {
    final selected = selectYouTubeAudioStream([
      YouTubeAudioStream(
        url: Uri.parse('https://media.test/audio.webm'),
        format: YouTubeAudioFormat.webm,
        bitrate: 256000,
      ),
      YouTubeAudioStream(
        url: Uri.parse('https://media.test/audio.m4a'),
        format: YouTubeAudioFormat.m4a,
        bitrate: 128000,
      ),
    ]);

    expect(selected?.url.path, '/audio.m4a');
    expect(selected?.format, YouTubeAudioFormat.m4a);
  });

  test('WebM is selected when no M4A stream exists', () {
    final selected = selectYouTubeAudioStream([
      YouTubeAudioStream(
        url: Uri.parse('https://media.test/low.webm'),
        format: YouTubeAudioFormat.webm,
        bitrate: 64000,
      ),
      YouTubeAudioStream(
        url: Uri.parse('https://media.test/high.webm'),
        format: YouTubeAudioFormat.webm,
        bitrate: 128000,
      ),
    ]);

    expect(selected?.url.path, '/high.webm');
    expect(selected?.format.fileExtension, 'webm');
  });

  test('each play or download resolves a fresh YouTube URL', () async {
    final gateway = _FakeYouTubeGateway(
      searchResults: const [],
      audioStreams: [
        YouTubeAudioStream(
          url: Uri.parse('https://media.test/first?token=1'),
          format: YouTubeAudioFormat.m4a,
          bitrate: 128000,
        ),
        YouTubeAudioStream(
          url: Uri.parse('https://media.test/second?token=2'),
          format: YouTubeAudioFormat.m4a,
          bitrate: 128000,
        ),
      ],
    );
    final resolver = TrackSourceResolver(youtubeGateway: gateway);
    final item = MediaItem(
      id: 'youtube:video_1',
      title: 'Authorized audio',
      extras: const {'source': youtubeSource, 'sourceId': 'video_1'},
    );

    final first = await resolver.resolve(item);
    final second = await resolver.resolve(item);

    expect(first.url.queryParameters['token'], '1');
    expect(second.url.queryParameters['token'], '2');
    expect(gateway.resolvedIds, ['video_1', 'video_1']);
    expect(item.extras, isNot(contains('url')));
  });

  test('validated media headers are preserved and applied by URL type', () {
    const headers = {'User-Agent': 'validated', 'Referer': 'youtube'};
    final stream = YouTubeAudioStream(
      url: Uri.parse('https://rr1---sn-test.googlevideo.com/videoplayback'),
      format: YouTubeAudioFormat.m4a,
      bitrate: 128000,
      headers: headers,
    );

    expect(stream.headers, headers);
    expect(
      headersForMediaUrl(stream.url),
      containsPair('User-Agent', youtubeMediaHeaders['User-Agent']),
    );
    expect(
      headersForMediaUrl(Uri.parse('https://cdn.test/audio.m4a')),
      isEmpty,
    );
  });

  test('direct music URLs still resolve to the existing MP3 format', () async {
    final resolver = TrackSourceResolver(
      youtubeGateway: _FakeYouTubeGateway(
        searchResults: const [],
        audioStreams: const [],
      ),
    );

    final source = await resolver.resolve(
      MediaItem(
        id: 'saavn:1',
        title: 'Saavn track',
        extras: const {'url': 'https://cdn.test/song.mp3'},
      ),
    );

    expect(source.url.path, '/song.mp3');
    expect(source.extension, 'mp3');
  });

  test('a track with no direct or YouTube source has a useful error', () async {
    final resolver = TrackSourceResolver(
      youtubeGateway: _FakeYouTubeGateway(
        searchResults: const [],
        audioStreams: const [],
      ),
    );

    await expectLater(
      resolver.resolve(MediaItem(id: 'broken', title: 'Broken')),
      throwsA(
        isA<TrackSourceResolutionException>().having(
          (error) => error.message,
          'message',
          contains('no audio'),
        ),
      ),
    );
  });

  test('extractor errors are classified by their real cause', () {
    expect(
      classifyYouTubeFailure(const YouTubeAudioUnavailableException()),
      YouTubeResolveFailure.noAudioStreams,
    );
    expect(
      classifyYouTubeFailure(
        VideoRequiresPurchaseException(VideoId.fromString('dQw4w9WgXcQ')),
      ),
      YouTubeResolveFailure.requiresPurchase,
    );
    expect(
      classifyYouTubeFailure(RequestLimitExceededException('slow down')),
      YouTubeResolveFailure.rateLimited,
    );
    expect(
      classifyYouTubeFailure(TransientFailureException('bad gateway')),
      YouTubeResolveFailure.transient,
    );
    expect(
      classifyYouTubeFailure(VideoUnavailableException('taken down')),
      YouTubeResolveFailure.unplayable,
    );
    expect(
      classifyYouTubeFailure(VideoUnplayableException('blocked')),
      YouTubeResolveFailure.unplayable,
    );
    expect(
      classifyYouTubeFailure(TimeoutException('too slow')),
      YouTubeResolveFailure.timedOut,
    );
    expect(
      classifyYouTubeFailure(StateError('unrecognised response')),
      YouTubeResolveFailure.unknown,
    );
  });

  test(
    'a permanent failure is reported accurately and is not retried',
    () async {
      final gateway = _FailingYouTubeGateway(
        const YouTubeResolutionException(YouTubeResolveFailure.unplayable),
      );
      final resolver = TrackSourceResolver(youtubeGateway: gateway);

      await expectLater(
        resolver.resolve(_youTubeItem()),
        throwsA(
          isA<TrackSourceResolutionException>().having(
            (error) => error.message,
            'message',
            contains('private, removed, or blocked in your region'),
          ),
        ),
      );
      expect(gateway.attempts, 1, reason: 'retrying a region lock never helps');
    },
  );

  test('a monetised video is not retried and says it needs buying', () async {
    final gateway = _FailingYouTubeGateway(
      const YouTubeResolutionException(YouTubeResolveFailure.requiresPurchase),
    );
    final resolver = TrackSourceResolver(youtubeGateway: gateway);

    await expectLater(
      resolver.resolve(_youTubeItem()),
      throwsA(
        isA<TrackSourceResolutionException>().having(
          (error) => error.message,
          'message',
          contains('purchased'),
        ),
      ),
    );
    expect(gateway.attempts, 1);
  });

  test('a rate limit is retried once and recovers', () async {
    final gateway = _FailingYouTubeGateway(
      const YouTubeResolutionException(YouTubeResolveFailure.rateLimited),
      thenSucceedWith: YouTubeAudioStream(
        url: Uri.parse('https://media.test/recovered.m4a'),
        format: YouTubeAudioFormat.m4a,
        bitrate: 128000,
      ),
    );
    final resolver = TrackSourceResolver(youtubeGateway: gateway);

    final source = await resolver.resolve(_youTubeItem());

    expect(source.url.path, '/recovered.m4a');
    expect(gateway.attempts, 2);
  });

  test(
    'a rate limit that never clears names itself instead of guessing',
    () async {
      final gateway = _FailingYouTubeGateway(
        const YouTubeResolutionException(YouTubeResolveFailure.rateLimited),
      );
      final resolver = TrackSourceResolver(youtubeGateway: gateway);

      await expectLater(
        resolver.resolve(_youTubeItem()),
        throwsA(
          isA<TrackSourceResolutionException>().having(
            (error) => error.message,
            'message',
            contains('rate-limiting'),
          ),
        ),
      );
      expect(gateway.attempts, youtubeResolveAttempts);
    },
  );

  test('the old catch-all wording is no longer shown for a failure', () async {
    final gateway = _FailingYouTubeGateway(
      const YouTubeResolutionException(YouTubeResolveFailure.unknown),
    );
    final resolver = TrackSourceResolver(youtubeGateway: gateway);

    await expectLater(
      resolver.resolve(_youTubeItem()),
      throwsA(
        isA<TrackSourceResolutionException>().having(
          (error) => error.message,
          'message',
          isNot(contains('region-restricted')),
        ),
      ),
    );
  });

  test('the resolve budget outlives the extractor retries it depends on', () {
    // The extractor retries five times and then re-runs the lookup through its
    // TV client. A budget shorter than that turns a pending success into a
    // reported failure.
    expect(youtubeResolveTimeout, greaterThan(const Duration(seconds: 30)));
  });
}

MediaItem _youTubeItem() => MediaItem(
  id: 'youtube:video_1',
  title: 'Authorized audio',
  extras: const {'source': youtubeSource, 'sourceId': 'video_1'},
);

class _FailingYouTubeGateway implements YouTubeGateway {
  _FailingYouTubeGateway(this.failure, {this.thenSucceedWith});

  final YouTubeResolutionException failure;
  final YouTubeAudioStream? thenSucceedWith;
  var attempts = 0;

  @override
  Future<List<YouTubeVideo>> search(String query, {required int limit}) async =>
      const [];

  @override
  Future<YouTubeAudioStream> resolveAudio(String videoId) async {
    attempts++;
    final stream = thenSucceedWith;
    if (stream != null && attempts > 1) return stream;
    throw failure;
  }
}

class _FakeYouTubeGateway implements YouTubeGateway {
  _FakeYouTubeGateway({
    required this.searchResults,
    required this.audioStreams,
  });

  final List<YouTubeVideo> searchResults;
  final List<YouTubeAudioStream> audioStreams;
  final resolvedIds = <String>[];

  @override
  Future<List<YouTubeVideo>> search(String query, {required int limit}) async =>
      searchResults.take(limit).toList(growable: false);

  @override
  Future<YouTubeAudioStream> resolveAudio(String videoId) async {
    resolvedIds.add(videoId);
    return audioStreams[resolvedIds.length - 1];
  }
}
