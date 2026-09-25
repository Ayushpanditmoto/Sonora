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
    try {
      final stream = await (youtubeGateway ?? YoutubeExplodeGateway())
          .resolveAudio(videoId)
          .timeout(const Duration(seconds: 20));
      return ResolvedTrackSource(
        url: stream.url,
        extension: stream.format.fileExtension,
        contentLength: stream.contentLength,
        headers: stream.headers,
      );
    } on YouTubeAudioUnavailableException {
      throw const TrackSourceResolutionException(
        'This video has no supported audio-only stream.',
      );
    } catch (_) {
      throw const TrackSourceResolutionException(
        'Could not resolve this YouTube video. It may be unavailable or region-restricted.',
      );
    }
  }
}

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
  return url == null ? null : ResolvedTrackSource(url: url, extension: 'mp3');
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
