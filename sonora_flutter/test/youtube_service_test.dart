import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonora_flutter/services/track_source.dart';
import 'package:sonora_flutter/services/youtube_api.dart';

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
