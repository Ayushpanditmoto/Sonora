import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:saavn_play/saavn_play.dart';

/// JioSaavn's unauthenticated web API, the same one jiosaavn.com calls itself.
const saavnApiUrl = 'https://www.jiosaavn.com/api.php';

/// Raised when JioSaavn answers with an `error` object instead of results.
///
/// It replies with HTTP 200 even for a rejected call, so an error payload
/// would otherwise reach the UI as an empty result list and read as "nothing
/// matched" rather than "the request was refused".
class SaavnRequestException implements Exception {
  const SaavnRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The JioSaavn calls Sonora makes.
///
/// This seam exists because `saavn_play` builds its own `Dio` from
/// [BaseOptions] and exposes no way to inject an [HttpClientAdapter]. Taking a
/// gateway instead lets the repository be tested against recorded payloads
/// without the suite reaching the network.
abstract interface class SaavnGateway {
  Future<Map<String, dynamic>> searchSongs(String query, {int page, int limit});

  Future<Map<String, dynamic>> searchAlbums(
    String query, {
    int page,
    int limit,
  });

  Future<Map<String, dynamic>> searchArtists(
    String query, {
    int page,
    int limit,
  });

  Future<Map<String, dynamic>> searchPlaylists(
    String query, {
    int page,
    int limit,
  });

  /// The album's tracks, keyed by the id album search reported.
  Future<Map<String, dynamic>> albumDetails(String id);

  /// The playlist's tracks.
  Future<Map<String, dynamic>> playlistDetails(String id);

  /// The artist's most played tracks.
  Future<Map<String, dynamic>> artistTopSongs(String id, {int page});
}

/// Talks to JioSaavn through `saavn_play`.
///
/// Most of the traffic goes through the package. Album and playlist details are
/// issued directly because `SaavnPlayClient` has no playlists endpoint at all,
/// and because its album normaliser prints two debug lines per song, which
/// would put a wall of noise in the logs of every album the user opens.
class SaavnPlayGateway implements SaavnGateway {
  SaavnPlayGateway({Dio? direct})
    : _client = SaavnPlayClient(_options),
      _direct = direct ?? Dio(_options);

  static final BaseOptions _options = BaseOptions(
    baseUrl: saavnApiUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    responseType: ResponseType.plain,
    queryParameters: {'_format': 'json', '_marker': '0', 'ctx': 'web6dot0'},
  );

  final SaavnPlayClient _client;
  final Dio _direct;

  @override
  Future<Map<String, dynamic>> searchSongs(
    String query, {
    int page = 0,
    int limit = 10,
  }) => _checked(() => _client.search.songs(query, page: page, limit: limit));

  @override
  Future<Map<String, dynamic>> searchAlbums(
    String query, {
    int page = 0,
    int limit = 10,
  }) => _checked(() => _client.search.albums(query, page: page, limit: limit));

  @override
  Future<Map<String, dynamic>> searchArtists(
    String query, {
    int page = 0,
    int limit = 10,
  }) => _checked(() => _client.search.artists(query, page: page, limit: limit));

  @override
  Future<Map<String, dynamic>> searchPlaylists(
    String query, {
    int page = 0,
    int limit = 10,
  }) =>
      _checked(() => _client.search.playlists(query, page: page, limit: limit));

  @override
  Future<Map<String, dynamic>> albumDetails(String id) =>
      _call('content.getAlbumDetails', {'albumid': id});

  @override
  Future<Map<String, dynamic>> playlistDetails(String id) =>
      _call('playlist.getDetails', {'listid': id});

  @override
  Future<Map<String, dynamic>> artistTopSongs(String id, {int page = 0}) =>
      _checked(() => _client.artists.artistSongs(id, page: page));

  Future<Map<String, dynamic>> _call(
    String call,
    Map<String, dynamic> parameters,
  ) async {
    final response = await _direct.get<String>(
      '/',
      queryParameters: {'api_version': 6, '__call': call, ...parameters},
    );
    return _verify(response.data);
  }

  /// Unwraps a decoded payload, turning JioSaavn's 200-with-an-error into a
  /// thrown [SaavnRequestException] so a refused call cannot pass for an empty
  /// result.
  static Map<String, dynamic> _verify(String? body) {
    final decoded = body == null ? null : jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const SaavnRequestException('Unexpected response from JioSaavn.');
    }
    final error = decoded['error'];
    if (error is Map && error['msg'] is String) {
      throw SaavnRequestException(error['msg'] as String);
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _checked(
    Future<Map<String, dynamic>> Function() send,
  ) async {
    final payload = await send();
    final error = payload['error'];
    if (error is Map && error['msg'] is String) {
      throw SaavnRequestException(error['msg'] as String);
    }
    return payload;
  }
}
