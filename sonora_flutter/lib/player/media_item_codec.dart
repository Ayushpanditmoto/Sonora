import 'dart:convert';

import 'package:audio_service/audio_service.dart';

/// Stores a track as a json string for local storage.
///
/// Only the fields the app renders are kept, so a stored entry stays small and
/// an older or malformed one is simply dropped when read back.
String encodeTrack(MediaItem track) => jsonEncode({
  'id': track.id,
  'title': track.title,
  if (track.artist != null) 'artist': track.artist,
  if (track.album != null) 'album': track.album,
  if (track.duration != null) 'duration': track.duration!.inMilliseconds,
  if (track.artUri != null) 'art': track.artUri!.toString(),
  if (track.extras != null) 'extras': track.extras,
});

MediaItem? decodeTrack(String value) {
  try {
    final json = jsonDecode(value) as Map<String, dynamic>;
    return MediaItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Unknown track',
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      duration: json['duration'] == null
          ? null
          : Duration(milliseconds: json['duration'] as int),
      artUri: json['art'] == null ? null : Uri.tryParse(json['art'] as String),
      extras: (json['extras'] as Map<dynamic, dynamic>?)
          ?.cast<String, dynamic>(),
    );
  } catch (_) {
    return null; // Skip anything an older version wrote.
  }
}

/// Stores the playing track and its queue, so the player and mini player can
/// come back on the same song after the app is closed.
String encodeLastSession({
  required MediaItem current,
  required List<MediaItem> queue,
}) => jsonEncode({
  'current': current.id,
  'queue': [for (final track in queue) encodeTrack(track)],
});

/// Reads back [encodeLastSession]. Returns null when nothing usable is stored.
({String? currentId, List<MediaItem> tracks})? decodeLastSession(String value) {
  try {
    final json = jsonDecode(value) as Map<String, dynamic>;
    final tracks = <MediaItem>[
      for (final entry in json['queue'] as List<dynamic>? ?? const [])
        ?decodeTrack(entry as String),
    ].whereType<MediaItem>().toList();
    if (tracks.isEmpty) return null;
    return (currentId: json['current'] as String?, tracks: tracks);
  } catch (_) {
    return null;
  }
}
