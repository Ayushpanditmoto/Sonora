import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

const youtubeSource = 'youtube';
const youtubeIdPrefix = '$youtubeSource:';

/// The unofficial YouTube integration is exposed only on Android for now.
final youtubeSearchAvailableProvider = Provider<bool>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
);

final youtubeRepositoryProvider = Provider<YouTubeRepository>(
  (ref) => YouTubeRepository(gateway: YoutubeExplodeGateway()),
);

final youtubeSearchResultsProvider =
    FutureProvider.family<List<MediaItem>, String>(
      (ref, query) =>
          ref.watch(youtubeRepositoryProvider).search(query, limit: 20),
    );

/// The small part of YouTube search Sonora needs. Keeping this behind an
/// interface makes stream selection and source mapping testable without a
/// network request.
abstract interface class YouTubeGateway {
  Future<List<YouTubeVideo>> search(String query, {required int limit});

  /// Resolves a fresh, short-lived audio URL for [videoId].
  Future<YouTubeAudioStream> resolveAudio(String videoId);
}

class YouTubeRepository {
  const YouTubeRepository({required this.gateway});

  final YouTubeGateway gateway;

  Future<List<MediaItem>> search(String query, {int limit = 20}) async {
    final videos = await gateway.search(query, limit: limit);
    return videos.map(youtubeMediaItem).toList(growable: false);
  }
}

class YouTubeVideo {
  const YouTubeVideo({
    required this.id,
    required this.title,
    required this.author,
    required this.pageUrl,
    required this.artworkUrl,
    this.duration,
    this.isLive = false,
  });

  final String id;
  final String title;
  final String author;
  final String pageUrl;
  final String artworkUrl;
  final Duration? duration;
  final bool isLive;
}

enum YouTubeAudioFormat { m4a, webm }

extension YouTubeAudioFormatName on YouTubeAudioFormat {
  String get fileExtension => switch (this) {
    YouTubeAudioFormat.m4a => 'm4a',
    YouTubeAudioFormat.webm => 'webm',
  };
}

/// Headers used by the extractor when it validates a media URL. The player and
/// downloader must send the same headers instead of independently choosing
/// their own User-Agent, which YouTube may reject with HTTP 403.
const youtubeMediaHeaders = <String, String>{
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36',
  'Cookie': 'CONSENT=YES+cb',
  'Accept': '*/*',
  'Accept-Encoding': 'identity',
  'Referer': 'https://www.youtube.com/',
};

Map<String, String> headersForMediaUrl(Uri url) =>
    url.host.toLowerCase().endsWith('.googlevideo.com')
    ? youtubeMediaHeaders
    : const {};

class YouTubeAudioStream {
  const YouTubeAudioStream({
    required this.url,
    required this.format,
    required this.bitrate,
    this.contentLength,
    this.headers = const {},
  });

  final Uri url;
  final YouTubeAudioFormat format;
  final int bitrate;

  /// Exact byte size advertised for this stream, when YouTube supplied it.
  final int? contentLength;
  final Map<String, String> headers;
}

/// Prefers AAC/M4A for broad Android and desktop player support, while
/// retaining WebM/Opus as a no-conversion fallback.
List<YouTubeAudioStream> orderYouTubeAudioStreams(
  Iterable<YouTubeAudioStream> candidates,
) {
  final byFormat = {
    for (final format in YouTubeAudioFormat.values)
      format: candidates.where((stream) => stream.format == format).toList(),
  };
  return [
    for (final format in YouTubeAudioFormat.values)
      for (final stream
          in byFormat[format]!..sort((a, b) => b.bitrate.compareTo(a.bitrate)))
        stream,
  ];
}

YouTubeAudioStream? selectYouTubeAudioStream(
  Iterable<YouTubeAudioStream> candidates,
) {
  final ordered = orderYouTubeAudioStreams(candidates);
  return ordered.isEmpty ? null : ordered.first;
}

class YouTubeAudioUnavailableException implements Exception {
  const YouTubeAudioUnavailableException();
}

/// Why a video could not be turned into a playable audio stream.
///
/// The extractor reports many genuinely different problems - it is
/// rate-limiting this device, it served a bot check instead of a manifest,
/// the video is private or region-locked, the video is monetised, or YouTube
/// simply had a bad moment. They used to collapse into one catch-all message
/// that always guessed "unavailable or region-restricted", which was wrong
/// most of the time and left the user with nothing to act on. The distinction
/// matters because the transient causes are worth retrying and the permanent
/// ones are not.
enum YouTubeResolveFailure {
  /// YouTube believes too many requests came from this IP.
  rateLimited,

  /// YouTube answered 5xx/connection reset; the problem is on their side.
  transient,

  /// The extractor needed longer than Sonora is willing to wait.
  timedOut,

  /// A monetised video. Not playable, and never will be.
  requiresPurchase,

  /// Private, deleted, taken down, or blocked in this region.
  unplayable,

  /// The video has no audio-only stream Sonora can play.
  noAudioStreams,

  /// Anything Sonora could not classify, such as a parser that no longer
  /// understands a response YouTube changed. Worth one retry.
  unknown,
}

extension YouTubeResolveFailureRetry on YouTubeResolveFailure {
  /// Whether retrying the same video could plausibly succeed.
  bool get isTransient => switch (this) {
    YouTubeResolveFailure.rateLimited ||
    YouTubeResolveFailure.transient ||
    YouTubeResolveFailure.timedOut ||
    YouTubeResolveFailure.unknown => true,
    YouTubeResolveFailure.requiresPurchase ||
    YouTubeResolveFailure.unplayable ||
    YouTubeResolveFailure.noAudioStreams => false,
  };
}

/// A resolution failure that keeps the real cause instead of flattening it.
///
/// [cause] is the original extractor exception, kept so the log keeps the
/// full YouTube response even when the user-facing message is brief.
class YouTubeResolutionException implements Exception {
  const YouTubeResolutionException(this.failure, {this.cause});

  final YouTubeResolveFailure failure;
  final Object? cause;

  @override
  String toString() => 'YouTubeResolutionException($failure, cause: $cause)';
}

/// Maps an extractor error onto the reason Sonora will act on.
///
/// Order matters: [VideoRequiresPurchaseException] and
/// [VideoUnavailableException] both extend [VideoUnplayableException], so the
/// more specific types have to be matched first.
YouTubeResolveFailure classifyYouTubeFailure(Object error) {
  if (error is YouTubeAudioUnavailableException) {
    return YouTubeResolveFailure.noAudioStreams;
  }
  if (error is VideoRequiresPurchaseException) {
    return YouTubeResolveFailure.requiresPurchase;
  }
  if (error is RequestLimitExceededException) {
    return YouTubeResolveFailure.rateLimited;
  }
  if (error is TransientFailureException) {
    return YouTubeResolveFailure.transient;
  }
  if (error is VideoUnavailableException) {
    return YouTubeResolveFailure.unplayable;
  }
  if (error is VideoUnplayableException) {
    return YouTubeResolveFailure.unplayable;
  }
  if (error is TimeoutException) {
    return YouTubeResolveFailure.timedOut;
  }
  return YouTubeResolveFailure.unknown;
}

/// The message shown for a failure, written to say what the user can do next
/// rather than to guess at a cause.
String youtubeFailureMessage(YouTubeResolveFailure failure) =>
    switch (failure) {
      YouTubeResolveFailure.rateLimited =>
        'YouTube is rate-limiting this device. Wait a moment, then try again.',
      YouTubeResolveFailure.transient =>
        'YouTube had a temporary problem. Try again in a moment.',
      YouTubeResolveFailure.timedOut =>
        'YouTube took too long to respond. Try again in a moment.',
      YouTubeResolveFailure.requiresPurchase =>
        'This video has to be purchased before it can be played.',
      YouTubeResolveFailure.unplayable =>
        'This video is private, removed, or blocked in your region.',
      YouTubeResolveFailure.noAudioStreams =>
        'This video has no supported audio-only stream.',
      YouTubeResolveFailure.unknown => 'Could not resolve this YouTube video. Check your connection and try again.',
    };

/// Records the real failure. This used to be discarded entirely, which is why
/// the app could only ever report that a video "may be unavailable" no matter
/// what YouTube actually did.
void logYouTubeFailure(String videoId, Object error, StackTrace stackTrace) {
  if (!kDebugMode) return;
  debugPrint('Sonora: YouTube resolution failed for $videoId: $error');
  debugPrintStack(stackTrace: stackTrace, label: 'YouTube resolution');
}

/// Adapter around the keyless, unofficial extractor package. A new client is
/// used per operation so its HTTP resources are always closed promptly.
class YoutubeExplodeGateway implements YouTubeGateway {
  @override
  Future<List<YouTubeVideo>> search(String query, {required int limit}) async {
    final youtube = YoutubeExplode();
    try {
      final videos = await youtube.search.search(query);
      final count = limit < 1 ? 1 : (limit > 20 ? 20 : limit);
      return [
        for (final video in videos)
          if (!video.isLive)
            YouTubeVideo(
              id: video.id.value,
              title: video.title,
              author: video.author,
              pageUrl: video.url,
              artworkUrl: video.thumbnails.highResUrl,
              duration: video.duration,
            ),
      ].take(count).toList(growable: false);
    } finally {
      youtube.close();
    }
  }

  @override
  Future<YouTubeAudioStream> resolveAudio(String videoId) async {
    final youtube = YoutubeExplode();
    try {
      // Do not pass several preferred clients here. Version 3.1.0 probes every
      // supplied client even after another one has succeeded; the iOS client can
      // spend roughly 14 seconds retrying a 403 before returning the manifest.
      // With no override, the package uses Android SDK-less first and falls back
      // to TV only if that client produces no streams.
      final manifest = await youtube.videos.streams.getManifest(videoId);
      // Only audio-only streams are used. The muxed progressive stream
      // (itag 18) looks like a usable last resort, but Googlevideo serves it
      // unreliably: replaying this downloader's exact request sequence produced
      // a valid MP4 on one attempt and a byte-displaced file on the next, with
      // no ftyp or moov box anywhere in it. Such a file is rejected by
      // ExoPlayer as an unrecognised format, both when downloaded and when
      // streamed, so preferring it trades a clear "unavailable" for a track that
      // silently never plays. The audio-only streams are DASH segments, are
      // served reliably, and are a fraction of the size.
      final audioOnly = [
        for (final stream in manifest.audioOnly)
          if (_formatFor(stream.container) case final format?)
            YouTubeAudioStream(
              url: stream.url,
              format: format,
              bitrate: stream.bitrate.bitsPerSecond,
              contentLength: stream.size.totalBytes,
              headers: youtubeMediaHeaders,
            ),
      ];
      final ordered = orderYouTubeAudioStreams(audioOnly);
      if (ordered.isEmpty) throw const YouTubeAudioUnavailableException();
      // The best stream is used without probing it first. Googlevideo answers
      // an identical request with 200 and then 403 depending only on how much
      // has been asked of it recently, so a reachability check reports a rate
      // limit as a dead URL and turns a working video into "unavailable". A
      // genuinely expired URL is already covered: the downloader re-resolves and
      // retries on a 403, and a file that is not media is rejected on its
      // container.
      return ordered.first;
    } on YouTubeAudioUnavailableException {
      rethrow;
    } catch (error, stackTrace) {
      // Every other extractor error is kept as a typed failure. Swallowing it
      // here is what previously produced a single catch-all message, so a
      // rate limit, a bot check and a private video were all reported to the
      // user as "unavailable or region-restricted".
      logYouTubeFailure(videoId, error, stackTrace);
      throw YouTubeResolutionException(
        classifyYouTubeFailure(error),
        cause: error,
      );
    } finally {
      youtube.close();
    }
  }

  YouTubeAudioFormat? _formatFor(StreamContainer container) =>
      switch (container) {
        StreamContainer.mp4 => YouTubeAudioFormat.m4a,
        StreamContainer.webM => YouTubeAudioFormat.webm,
        _ => null,
      };
}

/// Creates stable, source-aware metadata without storing YouTube's temporary
/// media URL. A later play or download resolves a new URL from [sourceId].
MediaItem youtubeMediaItem(YouTubeVideo video) => MediaItem(
  id: '$youtubeIdPrefix${video.id}',
  title: video.title.trim().isEmpty ? 'YouTube video' : video.title.trim(),
  artist: video.author.trim().isEmpty ? 'YouTube' : video.author.trim(),
  album: 'YouTube',
  duration: video.duration,
  artUri: Uri.tryParse(video.artworkUrl),
  extras: {
    'source': youtubeSource,
    'sourceId': video.id,
    'pageUrl': video.pageUrl,
    'art': video.artworkUrl,
    'accent': _youtubeAccent(video.id),
  },
);

int _youtubeAccent(String id) {
  const accents = [0xFF63E69D, 0xFFFF8066, 0xFFA58CFF, 0xFFFFD66B, 0xFF5AB4FF];
  return accents[id.hashCode.abs() % accents.length];
}
