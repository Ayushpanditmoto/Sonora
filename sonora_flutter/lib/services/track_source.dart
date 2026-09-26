import 'package:audio_service/audio_service.dart';

import 'youtube_api.dart';

typedef ResolveTrackStream = Future<ResolvedTrackSource> Function(
  MediaItem track,
);

class ResolvedTrackSource {
  const ResolvedTrackSource({
    required this.url,
    required this.extension,
    this.contentLength,
    this.headers = const {},
  });

  final Uri url;
  final String extension;
  final int? contentLength;
  final Map<String, String> headers;
}

class TrackSourceResolutionException implements Exception {
  const TrackSourceResolutionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Resolves either a stable direct URL already supplied by the music service or
/// a fresh YouTube URL. The returned URL is deliberately not written into the
/// [MediaItem], because YouTube media URLs expire.
class TrackSourceResolver {
  TrackSourceResolver({this.youtubeGateway});

  final YouTubeGateway? youtubeGateway;

  Future<ResolvedTrackSource> resolve(MediaItem track) async {
    if (isYouTubeTrack(track)) return _resolveYouTube(track);
    final source = directTrackSource(track);
    if (source == null) {
      throw const TrackSourceResolutionException(
        'This track has no audio available.',
      );
    }
    return source;
  }

  Future<ResolvedTrackSource> _resolveYouTube(MediaItem track) async {
    final videoId = youtubeVideoId(track);
    if (videoId == null || videoId.isEmpty) {
      throw const TrackSourceResolutionException(
        'This YouTube result has no valid video id.',
      );
    }
    final gateway = youtubeGateway ?? YoutubeExplodeGateway();
    var failure = YouTubeResolveFailure.unknown;
    for (var attempt = 0; attempt < youtubeResolveAttempts; attempt++) {
      try {
        final stream = await gateway
            .resolveAudio(videoId)
            .timeout(youtubeResolveTimeout);
        return ResolvedTrackSource(
          url: stream.url,
          extension: stream.format.fileExtension,
          contentLength: stream.contentLength,
          headers: stream.headers,
        );
      } on YouTubeAudioUnavailableException {
        // A property of the video itself, so it is reported directly instead
        // of being retried.
        throw const TrackSourceResolutionException(
          'This video has no supported audio-only stream.',
        );
      } catch (error, stackTrace) {
        failure = error is YouTubeResolutionException
            ? error.failure
            : classifyYouTubeFailure(error);
        logYouTubeFailure(videoId, error, stackTrace);
        // Rate limits, bot checks and YouTube's own bad moments usually clear
        // on a second attempt, and a resolve that works takes well under a
        // second, so one retry is cheap. A private or region-locked video
        // fails identically again, so it is not retried.
        if (!failure.isTransient) break;
      }
    }
    throw TrackSourceResolutionException(youtubeFailureMessage(failure));
  }
}

/// One retry. Enough to ride out a rate limit or a bot check, short enough
/// that a permanently broken video does not leave the player hanging.
const youtubeResolveAttempts = 2;

/// Long enough for the extractor to exhaust its own recovery before Sonora
/// gives up on it.
///
/// The extractor retries a failing request up to five times with backoff and
/// then re-runs the whole lookup through its TV client, so a slow resolve
/// legitimately takes tens of seconds. The previous 20s budget cut that
/// recovery short and the resulting timeout was then reported to the user as
/// an unavailable video, turning a request that was about to succeed into a
/// hard failure.
const youtubeResolveTimeout = Duration(seconds: 40);

bool isYouTubeTrack(MediaItem track) =>
    track.extras?['source'] == youtubeSource ||
    track.id.startsWith(youtubeIdPrefix);

String? youtubeVideoId(MediaItem track) {
  final sourceId = track.extras?['sourceId'];
  if (sourceId is String && sourceId.isNotEmpty) return sourceId;
  if (track.id.startsWith(youtubeIdPrefix)) {
    return track.id.substring(youtubeIdPrefix.length);
  }
  return null;
}

bool canResolveTrackSource(MediaItem track) =>
    isYouTubeTrack(track) || directTrackSource(track) != null;

/// Returns the already-stable direct source, if there is one. Playback uses this
/// synchronous path to preserve the existing Saavn load timing.
ResolvedTrackSource? directTrackSource(MediaItem track) {
  final url = _directUrl(track);
  return url == null
      ? null
      : ResolvedTrackSource(url: url, extension: _extensionFor(url));
}

/// The media container a url points at.
///
/// JioSaavn serves its audio in an `audio/mp4` container rather than the `.mp3`
/// this used to assume. Playback sniffs the real type, but a download is named
/// after this, so the container has to be read off the url rather than guessed
/// or a correctly downloaded track would be written out under the wrong name.
String _extensionFor(Uri url) {
  final name = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return 'mp3';
  final extension = name.substring(dot + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]+$').hasMatch(extension) ? extension : 'mp3';
}

Uri? _directUrl(MediaItem track) {
  final value = track.extras?['url'];
  if (value is! String || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri;
}
