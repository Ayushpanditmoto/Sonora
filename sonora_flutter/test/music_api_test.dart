import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonora_flutter/services/music_api.dart';
import 'package:sonora_flutter/services/saavn_gateway.dart';
import 'package:sonora_flutter/services/saavn_media_url.dart';
import 'package:sonora_flutter/services/track_source.dart';

/// A real `encrypted_media_url` and the url it decrypts to, captured from
/// JioSaavn so the DES round trip is checked against genuine data instead of
/// against itself.
const _encrypted320 =
    'ID2ieOjCrwfgWvL5sXl4B1ImC5QfbsDyrBAWC97DSvbuFjCjHV1Dc/ZM2Ut7gz3z/m6RImgLg8VKNUcLxkWCmBw7tS9a8Gtq';
const _decrypted320 =
    'https://aac.saavncdn.com/786/2f7463095ed2bfab1274c018551b00a2_96.mp4';
const _stream320 =
    'https://aac.saavncdn.com/786/2f7463095ed2bfab1274c018551b00a2_320.mp4';

void main() {
  group('decryptMediaUrl', () {
    test('decrypts a real JioSaavn media url', () {
      expect(decryptMediaUrl(_encrypted320), _decrypted320);
    });

    test('returns null for anything that is not one', () {
      expect(decryptMediaUrl(null), isNull);
      expect(decryptMediaUrl(''), isNull);
      expect(decryptMediaUrl('not base64 at all !!'), isNull);
      // Valid base64, but it does not decrypt to a url.
      expect(decryptMediaUrl('aGVsbG8gd29ybGQgaGVsbG8gd29ybGQ='), isNull);
    });
  });

  group('bestMediaUrl', () {
    test('asks for 320kbps when the track has it', () {
      expect(
        bestMediaUrl({'encrypted_media_url': _encrypted320, '320kbps': 'true'}),
        _stream320,
      );
    });

    test('leaves the bitrate alone when the track does not have it', () {
      // JioSaavn masters some tracks at 320kbps and not others, and the higher
      // bitrate variants of the same path 404 for the rest, so the flag the
      // API reports is what decides.
      for (final flag in <Object?>[null, 'false', false]) {
        expect(
          bestMediaUrl({'encrypted_media_url': _encrypted320, '320kbps': flag}),
          _decrypted320,
          reason: '320kbps=$flag must not request a missing variant',
        );
      }
    });

    test('is null without a media url', () {
      expect(bestMediaUrl(const {}), isNull);
    });
  });

  group('searchSongs', () {
    test('maps a JioSaavn song onto a playable MediaItem', () async {
      final gateway = _FakeGateway(songs: [_song(id: '47_T2N3p')]);

      final tracks = await MusicRepository(gateway: gateway)
          .searchSongs('hindi hits');

      expect(gateway.songQueries, [('hindi hits', 0, 20)]);
      final track = tracks.single;
      expect(track.id, '47_T2N3p');
      expect(track.title, 'Casa Tupka Anthemo');
      expect(track.artist, 'Yo Yo Honey Singh, Pritam');
      expect(track.album, 'Casa Tupka Anthemo');
      expect(track.duration, const Duration(minutes: 3, seconds: 3));
      expect(track.artUri, Uri.parse('https://cdn.test/cover-500x500.jpg'));
      expect(track.extras?['url'], _stream320);
      expect(track.extras?['art'], 'https://cdn.test/cover-500x500.jpg');
      expect(track.extras?['language'], 'hindi');
      expect(track.extras?['playCount'], '466013');
      expect(track.extras?['accent'], isA<int>());
    });

    test('keeps the bitrate the track was given', () async {
      final gateway = _FakeGateway(songs: [_song(id: 'low', has320: false)]);

      final tracks = await MusicRepository(gateway: gateway)
          .searchSongs('anything');

      expect(tracks.single.extras?['url'], _decrypted320);
    });

    test('skips songs with no playable media', () async {
      final gateway = _FakeGateway(
        songs: [
          _song(id: 'gone', mediaUrl: null),
          _song(id: 'also-gone', mediaUrl: 'bm90IGEgcmVhbCB1cmw='),
          _song(id: 'ok'),
        ],
      );

      final tracks = await MusicRepository(gateway: gateway).searchSongs('x');

      expect(tracks.map((track) => track.id), ['ok']);
    });

    test('decodes the entities JioSaavn leaves in titles', () async {
      final gateway = _FakeGateway(
        songs: [
          _song(id: 'quoted', title: 'Gehra Hua (From &quot;Dhurandhar&quot;)'),
        ],
      );

      final tracks = await MusicRepository(gateway: gateway).searchSongs('x');

      expect(tracks.single.title, 'Gehra Hua (From "Dhurandhar")');
    });

    test(
      'falls back to the subtitle when nothing credits a primary artist',
      () async {
        final gateway = _FakeGateway(songs: [_song(id: 'sub', artists: null)]);

        final tracks = await MusicRepository(gateway: gateway).searchSongs('x');

        expect(tracks.single.artist, 'Yo Yo Honey Singh');
      },
    );

    test('reports an unusable track as unknown rather than blank', () async {
      // Playable, so it survives, but with nothing but an id and a media url to
      // build the rest of the label from.
      final gateway = _FakeGateway(songs: [_song(id: 'bare', minimal: true)]);

      final tracks = await MusicRepository(gateway: gateway).searchSongs('x');

      expect(tracks.single.artist, 'Unknown artist');
      expect(tracks.single.album, 'Single');
      expect(tracks.single.duration, Duration.zero);
      expect(tracks.single.artUri, isNull);
      expect(tracks.single.extras?['url'], _stream320);
    });
  });

  group('searchCollections', () {
    test('maps an album with its credited artists', () async {
      final gateway = _FakeGateway(
        albums: [
          {
            'id': '38682222',
            'title': 'Bhediya',
            'image': 'https://cdn.test/bhediya-150x150.jpg',
            'more_info': {
              'song_count': '6',
              'artistMap': {
                'primary_artists': [
                  {'id': 'ar-1', 'name': 'Sachin-Jigar'},
                ],
              },
            },
          },
        ],
      );

      final albums = await MusicRepository(gateway: gateway)
          .searchCollections('arijit', CollectionKind.album);

      expect(gateway.albumQueries, [('arijit', 0, 10)]);
      final album = albums.single;
      expect(album.id, '38682222');
      expect(album.name, 'Bhediya');
      expect(album.subtitle, 'Sachin-Jigar');
      expect(album.imageUrl, 'https://cdn.test/bhediya-500x500.jpg');
      expect(album.kind, CollectionKind.album);
    });

    test('maps an artist by its role', () async {
      final gateway = _FakeGateway(
        artists: [
          {
            'id': '459320',
            'name': 'Arijit Singh',
            'role': 'Singer',
            'image': 'https://cdn.test/arijit-50x50.jpg',
          },
        ],
      );

      final artists = await MusicRepository(gateway: gateway)
          .searchCollections('arijit', CollectionKind.artist);

      expect(artists.single.subtitle, 'Singer');
      expect(artists.single.id, '459320');
    });

    test('maps a playlist by how many songs it holds', () async {
      final gateway = _FakeGateway(
        playlists: [
          {
            'id': '110858205',
            'title': 'Trending Today',
            'image': 'https://cdn.test/trending-150x150.jpg',
            'more_info': {'song_count': '601'},
          },
        ],
      );

      final playlists = await MusicRepository(gateway: gateway)
          .searchCollections('hits', CollectionKind.playlist);

      expect(playlists.single.subtitle, '601 songs');
    });

    test('drops a collection with no id, which cannot be opened', () async {
      final gateway = _FakeGateway(
        albums: [
          {'title': 'No id here'},
          {'id': '38682222', 'title': 'Bhediya'},
        ],
      );

      final albums = await MusicRepository(gateway: gateway)
          .searchCollections('x', CollectionKind.album);

      expect(albums.map((album) => album.id), ['38682222']);
    });
  });

  group('collectionSongs', () {
    test('reads an album out of its list', () async {
      final gateway = _FakeGateway(
        albumPayload: {
          'list': [_song(id: 'a')],
        },
      );

      final tracks = await MusicRepository(gateway: gateway)
          .collectionSongs('38682222', CollectionKind.album);

      expect(gateway.albumIds, ['38682222']);
      expect(tracks.single.id, 'a');
    });

    test('reads a playlist out of its list', () async {
      final gateway = _FakeGateway(
        playlistPayload: {
          'list': [_song(id: 'p')],
        },
      );

      final tracks = await MusicRepository(gateway: gateway)
          .collectionSongs('3379491', CollectionKind.playlist);

      expect(gateway.playlistIds, ['3379491']);
      expect(tracks.single.id, 'p');
    });

    test("reads an artist's ranked tracks out of topSongs", () async {
      final gateway = _FakeGateway(
        artistSongsPayload: {
          'topSongs': {
            'songs': [_song(id: 't1'), _song(id: 't2')],
          },
        },
      );

      final tracks = await MusicRepository(gateway: gateway)
          .collectionSongs('459320', CollectionKind.artist);

      expect(gateway.artistIds, ['459320']);
      expect(tracks.map((track) => track.id), ['t1', 't2']);
    });

    test('survives a collection with no tracks', () async {
      final gateway = _FakeGateway(albumPayload: const {});

      final tracks = await MusicRepository(gateway: gateway)
          .collectionSongs('1', CollectionKind.album);

      expect(tracks, isEmpty);
    });
  });

  group('playable sources', () {
    test('a JioSaavn stream is named for the container it is served in', () {
      final source = directTrackSource(_mediaItem('47_T2N3p', _stream320));

      expect(source, isNotNull);
      // Not the mp3 the old proxy served, and not a hardcoded guess: a
      // downloaded track is written out under this extension.
      expect(source!.extension, 'mp4');
      expect(source.url, Uri.parse(_stream320));
    });

    test('a track with no url still cannot be resolved', () {
      expect(directTrackSource(_mediaItem('x', '')), isNull);
      expect(
        directTrackSource(_mediaItem('x', 'ftp://example.test/a.mp3')),
        isNull,
      );
    });
  });
}

/// A JioSaavn song result, shaped like the real `search.getResults` payload.
Map<String, dynamic> _song({
  required String id,
  String title = 'Casa Tupka Anthemo',
  String subtitle = 'Yo Yo Honey Singh - Casa Tupka Anthemo',
  String? mediaUrl = _encrypted320,
  bool has320 = true,
  String? artists = 'Yo Yo Honey Singh, Pritam',
  bool minimal = false,
}) {
  if (minimal) {
    return {
      'id': id,
      'title': title,
      'more_info': {'encrypted_media_url': _encrypted320, '320kbps': 'true'},
    };
  }
  return {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'type': 'song',
    'image': 'https://cdn.test/cover-150x150.jpg',
    'language': 'hindi',
    'play_count': '466013',
    'more_info': {
      'duration': '183',
      'album': 'Casa Tupka Anthemo',
      '320kbps': has320 ? 'true' : 'false',
      'encrypted_media_url': ?mediaUrl,
      if (artists != null)
        'artistMap': {
          'primary_artists': [
            for (final name in artists.split(', '))
              {'id': 'ar-$name', 'name': name},
          ],
        },
    },
  };
}

MediaItem _mediaItem(String id, String url) => MediaItem(
  id: id,
  title: 'Casa Tupka Anthemo',
  artist: 'Yo Yo Honey Singh',
  album: 'Casa Tupka Anthemo',
  duration: const Duration(minutes: 3, seconds: 3),
  extras: {'url': url},
);

/// Stands in for JioSaavn, recording what was asked of it.
class _FakeGateway implements SaavnGateway {
  _FakeGateway({
    List<Map<String, dynamic>>? songs,
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
    this.albumPayload = const {},
    this.playlistPayload = const {},
    this.artistSongsPayload = const {},
  }) : songs = songs ?? const [];

  final List<Map<String, dynamic>> songs;
  final List<Map<String, dynamic>> albums;
  final List<Map<String, dynamic>> artists;
  final List<Map<String, dynamic>> playlists;
  final Map<String, dynamic> albumPayload;
  final Map<String, dynamic> playlistPayload;
  final Map<String, dynamic> artistSongsPayload;

  final List<(String, int, int)> songQueries = [];
  final List<(String, int, int)> albumQueries = [];
  final List<String> albumIds = [];
  final List<String> playlistIds = [];
  final List<String> artistIds = [];

  @override
  Future<Map<String, dynamic>> searchSongs(
    String query, {
    int page = 0,
    int limit = 10,
  }) async {
    songQueries.add((query, page, limit));
    return {'total': songs.length, 'results': songs};
  }

  @override
  Future<Map<String, dynamic>> searchAlbums(
    String query, {
    int page = 0,
    int limit = 10,
  }) async {
    albumQueries.add((query, page, limit));
    return {'results': albums};
  }

  @override
  Future<Map<String, dynamic>> searchArtists(
    String query, {
    int page = 0,
    int limit = 10,
  }) async => {'results': artists};

  @override
  Future<Map<String, dynamic>> searchPlaylists(
    String query, {
    int page = 0,
    int limit = 10,
  }) async => {'results': playlists};

  @override
  Future<Map<String, dynamic>> albumDetails(String id) async {
    albumIds.add(id);
    return albumPayload;
  }

  @override
  Future<Map<String, dynamic>> playlistDetails(String id) async {
    playlistIds.add(id);
    return playlistPayload;
  }

  @override
  Future<Map<String, dynamic>> artistTopSongs(String id, {int page = 0}) async {
    artistIds.add(id);
    return artistSongsPayload;
  }
}
