import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonora_flutter/services/music_api.dart';

void main() {
  test('album songs come from /albums and map to playable tracks', () async {
    final adapter = _RecordingAdapter({
      'success': true,
      'data': {
        'songs': [_song('a'), _song('b', hasStream: false)],
      },
    });

    final tracks = await MusicRepository(client: _client(adapter))
        .collectionSongs('1139549', CollectionKind.album);

    expect(adapter.lastRequest?.path, '/albums');
    expect(adapter.lastRequest?.queryParameters['id'], '1139549');
    expect(
      tracks,
      hasLength(1),
      reason: 'songs without a stream url are skipped',
    );

    final track = tracks.single;
    expect(track.id, 'a');
    expect(track.title, 'Song a');
    expect(track.artist, 'Arijit Singh');
    expect(track.album, 'After dark');
    expect(track.duration, const Duration(seconds: 214));
    expect(track.artUri, Uri.parse('https://cdn.test/a.jpg'));
    expect(track.extras?['url'], 'https://cdn.test/a.mp3');
    expect(track.extras?['playCount'], 42);
  });

  test('playlists use /playlists and artists use their topSongs', () async {
    final playlistAdapter = _RecordingAdapter({
      'success': true,
      'data': {
        'songs': [_song('p')],
      },
    });
    final playlistTracks = await MusicRepository(
      client: _client(playlistAdapter),
    ).collectionSongs('3379491', CollectionKind.playlist);
    expect(playlistAdapter.lastRequest?.path, '/playlists');
    expect(playlistTracks.single.id, 'p');

    final artistAdapter = _RecordingAdapter({
      'success': true,
      'data': {
        'topSongs': [_song('t')],
      },
    });
    final artistTracks = await MusicRepository(client: _client(artistAdapter))
        .collectionSongs('459320', CollectionKind.artist);
    expect(artistAdapter.lastRequest?.path, '/artists');
    expect(artistTracks.single.id, 't');
  });

  test('search results without a stream url are skipped', () async {
    final adapter = _RecordingAdapter({
      'success': true,
      'data': {
        'results': [_song('gone', hasStream: false), _song('ok')],
      },
    });

    final tracks = await MusicRepository(client: _client(adapter))
        .searchSongs('hindi hits');

    expect(adapter.lastRequest?.path, '/search/songs');
    expect(tracks.map((track) => track.id), ['ok']);
  });
}

Dio _client(HttpClientAdapter adapter) => Dio()..httpClientAdapter = adapter;

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.payload);

  final Map<String, dynamic> payload;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _song(String id, {bool hasStream = true}) => {
  'id': id,
  'name': 'Song $id',
  'type': 'song',
  'duration': 214,
  'language': 'hindi',
  'playCount': 42,
  'album': {'id': 'al-1', 'name': 'After dark'},
  'artists': {
    'primary': [
      {'id': 'ar-1', 'name': 'Arijit Singh'},
    ],
    'featured': <Map<String, dynamic>>[],
    'all': <Map<String, dynamic>>[],
  },
  'image': [
    {'quality': '150x150', 'url': 'https://cdn.test/$id-150.jpg'},
    {'quality': '500x500', 'url': 'https://cdn.test/$id.jpg'},
  ],
  'downloadUrl': hasStream
      ? [
          {'quality': '320kbps', 'url': 'https://cdn.test/$id.mp3'},
        ]
      : <Map<String, dynamic>>[],
};
