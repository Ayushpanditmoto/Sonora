import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'saavn_gateway.dart';
import 'saavn_media_url.dart';

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
      .searchCollections('Hindi', CollectionKind.album),
);

final artistsProvider = FutureProvider<List<MusicCollection>>(
  (ref) => ref
      .watch(musicRepositoryProvider)
      .searchCollections('Arijit Singh', CollectionKind.artist),
);

final playlistsProvider = FutureProvider<List<MusicCollection>>(
  (ref) => ref
      .watch(musicRepositoryProvider)
      .searchCollections('hits', CollectionKind.playlist),
);

final searchResultsProvider = FutureProvider.family<List<MediaItem>, String>(
  (ref, query) =>
      ref.watch(musicRepositoryProvider).searchSongs(query, limit: 20),
);

typedef CollectionSearchKey = ({String query, CollectionKind kind});

final searchCollectionsProvider =
    FutureProvider.family<List<MusicCollection>, CollectionSearchKey>(
      (ref, key) => ref
          .watch(musicRepositoryProvider)
          .searchCollections(key.query, key.kind, limit: 20),
    );

/// Identifies a collection to fetch songs for. A record gives it value
/// equality, which Riverpod families require.
typedef CollectionKey = ({String id, CollectionKind kind});

final collectionTracksProvider =
    FutureProvider.family<List<MediaItem>, CollectionKey>(
      (ref, key) =>
          ref.watch(musicRepositoryProvider).collectionSongs(key.id, key.kind),
    );

/// Reads the JioSaavn catalogue and maps it onto the [MediaItem]s the player
/// and the rest of the UI already speak.
///
/// JioSaavn identifies a song by an opaque token rather than a number, sends
/// its media url DES encrypted under `more_info.encrypted_media_url` instead of
/// as a ready url, and names its fields differently from the `saavn.sumit.co`
/// proxy this replaced. All of that is absorbed here so nothing above this
/// class has to know about it.
class MusicRepository {
  MusicRepository({SaavnGateway? gateway})
    : _gateway = gateway ?? SaavnPlayGateway();

  final SaavnGateway _gateway;

  /// The albums, artists or playlists matching [query].
  Future<List<MusicCollection>> searchCollections(
    String query,
    CollectionKind kind, {
    int limit = 10,
  }) async {
    final payload = switch (kind) {
      CollectionKind.album => await _gateway.searchAlbums(query, limit: limit),
      CollectionKind.artist => await _gateway.searchArtists(
        query,
        limit: limit,
      ),
      CollectionKind.playlist => await _gateway.searchPlaylists(
        query,
        limit: limit,
      ),
    };
    return _results(payload)
        .map((json) => _toCollection(json, kind))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  /// The songs matching [query].
  Future<List<MediaItem>> searchSongs(
    String query, {
    int page = 0,
    int limit = 20,
  }) async => _playable(
    _results(await _gateway.searchSongs(query, page: page, limit: limit)),
  );

  /// Loads every song of the collection [id].
  ///
  /// An album returns its full track list, a playlist its tracks, and an
  /// artist the ten tracks JioSaavn ranks highest. None of the three accept a
  /// caller supplied page size, so the collection is as long as JioSaavn says.
  Future<List<MediaItem>> collectionSongs(
    String id,
    CollectionKind kind,
  ) async {
    final payload = switch (kind) {
      CollectionKind.album => await _gateway.albumDetails(id),
      CollectionKind.playlist => await _gateway.playlistDetails(id),
      CollectionKind.artist => await _gateway.artistTopSongs(id),
    };
    return _playable(_songs(payload));
  }

  /// The result list of a search response.
  List<Map<String, dynamic>> _results(Map<String, dynamic> payload) =>
      _list(payload['results']);

  /// The tracks of a collection response.
  ///
  /// Album and playlist details carry them in `list`, while an artist's ranked
  /// tracks nest them under `topSongs.songs`.
  List<Map<String, dynamic>> _songs(Map<String, dynamic> payload) {
    final topSongs = payload['topSongs'];
    if (topSongs is Map) {
      final nested = _list(topSongs['songs']);
      if (nested.isNotEmpty) return nested;
    }
    final direct = _list(payload['songs']);
    return direct.isNotEmpty ? direct : _list(payload['list']);
  }

  List<Map<String, dynamic>> _list(Object? value) =>
      (value as List?)?.whereType<Map<String, dynamic>>().toList() ??
      const <Map<String, dynamic>>[];

  /// Maps song json to [MediaItem]s, dropping the ones without a media url
  /// because they cannot be played.
  List<MediaItem> _playable(List<Map<String, dynamic>> songs) => songs
      .map(_toMediaItem)
      .where((item) => (item.extras?['url'] as String? ?? '').isNotEmpty)
      .toList(growable: false);

  MediaItem _toMediaItem(Map<String, dynamic> json) {
    final moreInfo = _map(json['more_info']);
    final streamUrl = bestMediaUrl(moreInfo) ?? '';
    final artUrl = _artUrl(json['image']);
    final id = json['id'] as String? ?? streamUrl;
    final artist = _artistNames(moreInfo, json);

    return MediaItem(
      id: id,
      // JioSaavn leaves html entities in its text, for example
      // `Gehra Hua (From &quot;Dhurandhar&quot;)`, so it is decoded before it
      // reaches a label.
      title: _decode(
        _text(json['title'] ?? json['name'] ?? json['song']) ?? 'Unknown track',
      ),
      artist: artist.isEmpty ? 'Unknown artist' : artist,
      album: _decode(_text(moreInfo['album']) ?? 'Single'),
      duration: _duration(moreInfo['duration'] ?? json['duration']),
      artUri: artUrl.isEmpty ? null : Uri.tryParse(artUrl),
      extras: {
        'url': streamUrl,
        'art': artUrl,
        'accent': _accentFor(id),
        'language': json['language'],
        'playCount': json['play_count'] ?? json['playCount'],
      },
    );
  }

  MusicCollection _toCollection(
    Map<String, dynamic> json,
    CollectionKind kind,
  ) {
    final moreInfo = _map(json['more_info']);
    final id = json['id'] as String? ?? '';
    final imageUrl = _artUrl(json['image']);
    final credits = _artistNames(moreInfo, json);
    final subtitle = switch (kind) {
      CollectionKind.album => credits.isEmpty ? 'Album' : credits,
      CollectionKind.artist => _text(json['role']) ?? 'Artist',
      CollectionKind.playlist => '${_songCount(json, moreInfo)} songs',
    };

    return MusicCollection(
      id: id,
      name: _decode(
        _text(json['name'] ?? json['title'] ?? json['song']) ?? 'Untitled',
      ),
      imageUrl: imageUrl,
      subtitle: subtitle,
      kind: kind,
    );
  }

  /// The credited artists, joined for display.
  ///
  /// JioSaavn spells the map `artistMap`, while the models shipped alongside it
  /// expect `artist_map`, so both spellings are accepted. A record that credits
  /// nobody structurally falls back to the leading part of the
  /// `artist - title` subtitle.
  String _artistNames(
    Map<String, dynamic> moreInfo,
    Map<String, dynamic> json,
  ) {
    final map = moreInfo['artistMap'] ?? moreInfo['artist_map'];
    final names = map is Map
        ? (map['primary_artists'] as List? ?? const [])
              .whereType<Map>()
              .map((artist) => _text(artist['name']) ?? '')
              .where((name) => name.isNotEmpty)
              .toList()
        : const <String>[];
    if (names.isNotEmpty) return _decode(names.join(', '));

    final subtitle = _text(json['subtitle']);
    if (subtitle == null) return '';
    return _decode(subtitle.split(RegExp(r'\s+[-–]\s+')).first.trim());
  }

  /// How many tracks the collection holds.
  String _songCount(Map<String, dynamic> json, Map<String, dynamic> moreInfo) {
    final value =
        moreInfo['song_count'] ?? json['song_count'] ?? json['list_count'];
    return switch (value) {
      final num number => number.round().toString(),
      final String text => text.isEmpty ? '0' : text,
      _ => '0',
    };
  }

  /// The artwork url, preferring the largest crop JioSaavn serves.
  ///
  /// Search responses carry the 150x150 variant, which is soft on a phone, and
  /// the same path serves a 500x500 one. A shape other than a plain url is
  /// tolerated, because not every response uses one.
  String _artUrl(Object? image) {
    if (image is String) {
      if (image.isEmpty) return '';
      return image.contains('150x150')
          ? image.replaceAll('150x150', '500x500')
          : image;
    }
    for (final value in (image as List?)?.reversed ?? const <Object?>[]) {
      if (value is Map && value['url'] is String) return value['url'] as String;
    }
    return '';
  }

  Map<String, dynamic> _map(Object? value) =>
      value is Map ? value.cast<String, dynamic>() : const <String, dynamic>{};

  String? _text(Object? value) {
    if (value == null) return null;
    final text = value is String ? value : value.toString();
    return text.isEmpty ? null : text;
  }

  /// A track length, which JioSaavn reports as a string of seconds.
  Duration _duration(Object? value) => Duration(
    seconds: switch (value) {
      final num number => number.round(),
      final String text => int.tryParse(text) ?? 0,
      _ => 0,
    },
  );

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
