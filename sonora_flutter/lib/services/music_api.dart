import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final musicRepositoryProvider = Provider<MusicRepository>(
  (ref) => MusicRepository(),
);

final catalogProvider = FutureProvider<List<MediaItem>>(
  (ref) =>
      ref.watch(musicRepositoryProvider).searchSongs('Hindi hits', limit: 24),
);

final albumsProvider = FutureProvider<List<MusicCollection>>(
  (ref) => ref
      .watch(musicRepositoryProvider)
      .searchCollections('/search/albums', 'Hindi', CollectionKind.album),
);

final artistsProvider = FutureProvider<List<MusicCollection>>(
  (ref) => ref
      .watch(musicRepositoryProvider)
      .searchCollections(
        '/search/artists',
        'Arijit Singh',
        CollectionKind.artist,
      ),
);

final playlistsProvider = FutureProvider<List<MusicCollection>>(
  (ref) => ref
      .watch(musicRepositoryProvider)
      .searchCollections('/search/playlists', 'hits', CollectionKind.playlist),
);

final searchResultsProvider = FutureProvider.family<List<MediaItem>, String>(
  (ref, query) =>
      ref.watch(musicRepositoryProvider).searchSongs(query, limit: 20),
);

/// Identifies a collection to fetch songs for. A record gives it value
/// equality, which Riverpod families require.
typedef CollectionKey = ({String id, CollectionKind kind});

final collectionTracksProvider =
    FutureProvider.family<List<MediaItem>, CollectionKey>(
      (ref, key) =>
          ref.watch(musicRepositoryProvider).collectionSongs(key.id, key.kind),
    );

class MusicRepository {
  MusicRepository({Dio? client})
    : _client =
          client ??
          Dio(
            BaseOptions(
              baseUrl: 'https://saavn.sumit.co/api',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );

  final Dio _client;

  Future<List<MusicCollection>> searchCollections(
    String path,
    String query,
    CollectionKind kind, {
    int limit = 10,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      path,
      queryParameters: {'query': query, 'page': 0, 'limit': limit},
    );
    final payload = response.data?['data'] as Map<String, dynamic>?;
    final results = payload?['results'] as List<dynamic>? ?? const [];
    return results
        .whereType<Map<String, dynamic>>()
        .map((json) {
          final artists = json['artists'] as Map<String, dynamic>?;
          final primary = artists?['primary'] as List<dynamic>? ?? const [];
          final names = primary
              .whereType<Map<String, dynamic>>()
              .map((artist) => artist['name'] as String? ?? '')
              .where((name) => name.isNotEmpty)
              .join(', ');
          final images = json['image'] as List<dynamic>? ?? const [];
          final subtitle = switch (kind) {
            CollectionKind.album => names.isEmpty ? 'Album' : names,
            CollectionKind.artist => json['role'] as String? ?? 'Artist',
            CollectionKind.playlist => '${json['songCount'] ?? 0} songs',
          };
          return MusicCollection(
            id: json['id'] as String? ?? '',
            name: _decode(json['name'] as String? ?? 'Untitled'),
            imageUrl: _lastUrl(images),
            subtitle: _decode(subtitle),
            kind: kind,
          );
        })
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<MediaItem>> searchSongs(
    String query, {
    int page = 0,
    int limit = 20,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/search/songs',
      queryParameters: {'query': query, 'page': page, 'limit': limit},
    );
    final payload = response.data?['data'] as Map<String, dynamic>?;
    final results = payload?['results'] as List<dynamic>? ?? const [];
    return _playable(results);
  }

  /// Loads every song of the collection [id].
  ///
  /// Albums return all their songs in `songs`, artists return their ten most
  /// played tracks in `topSongs`, and playlists honour [limit].
  Future<List<MediaItem>> collectionSongs(
    String id,
    CollectionKind kind, {
    int limit = 50,
  }) async {
    final (path, field) = switch (kind) {
      CollectionKind.album => ('/albums', 'songs'),
      CollectionKind.playlist => ('/playlists', 'songs'),
      CollectionKind.artist => ('/artists', 'topSongs'),
    };
    final response = await _client.get<Map<String, dynamic>>(
      path,
      queryParameters: {'id': id, 'page': 0, 'limit': limit},
    );
    final payload = response.data?['data'] as Map<String, dynamic>?;
    return _playable(payload?[field] as List<dynamic>? ?? const []);
  }

  /// Maps raw song json to [MediaItem]s, dropping the ones without a stream
  /// url because they cannot be played.
  List<MediaItem> _playable(List<dynamic> songs) => songs
      .whereType<Map<String, dynamic>>()
      .map(_toMediaItem)
      .where((item) => (item.extras?['url'] as String? ?? '').isNotEmpty)
      .toList(growable: false);

  MediaItem _toMediaItem(Map<String, dynamic> json) {
    final album = json['album'] as Map<String, dynamic>?;
    final artists = json['artists'] as Map<String, dynamic>?;
    final primary = artists?['primary'] as List<dynamic>? ?? const [];
    final artistNames = primary
        .whereType<Map<String, dynamic>>()
        .map((artist) => artist['name'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .join(', ');
    final images = json['image'] as List<dynamic>? ?? const [];
    final downloads = json['downloadUrl'] as List<dynamic>? ?? const [];
    final artUrl = _lastUrl(images);
    final streamUrl = _lastUrl(downloads);
    final id = json['id'] as String? ?? streamUrl;

    return MediaItem(
      id: id,
      title: _decode(json['name'] as String? ?? 'Unknown track'),
      artist: artistNames.isEmpty ? 'Unknown artist' : _decode(artistNames),
      album: _decode(album?['name'] as String? ?? 'Single'),
      duration: Duration(seconds: (json['duration'] as num?)?.round() ?? 0),
      artUri: artUrl.isEmpty ? null : Uri.tryParse(artUrl),
      extras: {
        'url': streamUrl,
        'art': artUrl,
        'accent': _accentFor(id),
        'language': json['language'],
        'playCount': json['playCount'],
      },
    );
  }

  String _lastUrl(List<dynamic> values) {
    for (final value in values.reversed) {
      if (value is Map<String, dynamic> && value['url'] is String) {
        return value['url'] as String;
      }
    }
    return '';
  }

  int _accentFor(String id) {
    const accents = [
      0xFF63E69D,
      0xFFFF8066,
      0xFFA58CFF,
      0xFFFFD66B,
      0xFF5AB4FF,
    ];
    return accents[id.hashCode.abs() % accents.length];
  }

  String _decode(String value) => value
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
}

enum CollectionKind { album, artist, playlist }

class MusicCollection {
  const MusicCollection({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.subtitle,
    required this.kind,
  });

  final String id;
  final String name;
  final String imageUrl;
  final String subtitle;
  final CollectionKind kind;
}
