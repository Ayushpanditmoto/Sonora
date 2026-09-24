import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player/media_item_codec.dart';

/// Reports bytes received and the total expected, where the total is -1 when the
/// server does not say.
typedef DownloadProgress = void Function(int received, int total);

/// Writes the bytes at [url] to [path], reporting progress along the way, and
/// returns how many bytes it wrote. Throws when the download fails.
typedef DownloadFetcher = Future<int> Function(
  String url,
  String path,
  DownloadProgress onProgress,
);

/// Tracks kept on the device so they play without a connection.
///
/// The audio files live in the app's support directory and the metadata in
/// [SharedPreferences], so both are private to the app and are removed when it
/// is uninstalled. The fetcher and the directory are injected so the store can
/// be exercised without a network or any platform plugin.
class DownloadStore extends ChangeNotifier {
  DownloadStore({
    DownloadFetcher? fetcher,
    Future<Directory> Function()? directory,
  }) : _fetch = fetcher ?? _fetchToFile,
       _directory = directory ?? _defaultDirectory;

  static const _prefsKey = 'sonora.downloads';

  final DownloadFetcher _fetch;
  final Future<Directory> Function() _directory;

  final _tracks = <String, MediaItem>{};
  final _sizes = <String, int>{};
  final _progress = <String, double>{};
  final _errors = <String, String>{};
  final _paths = <String, String>{};

  /// Downloads whose server has not supplied a total size. Their ring stays
  /// indeterminate rather than presenting an inaccurate fraction.
  final _indeterminateProgress = <String>{};

  /// Bytes received so far by downloads that are still running.
  final _receivedBytes = <String, int>{};

  bool _batchRunning = false;
  int? _batchPosition;
  int? _batchTotal;
  Set<String> _batchTrackIds = const {};

  /// True once the stored downloads have been read back.
  bool _ready = false;

  /// Set when something changed before [load] finished, so the change is written
  /// out once the stored downloads have been merged in.
  bool _changedWhileLoading = false;

  /// The downloaded tracks, in the order they were downloaded.
  List<MediaItem> get tracks => List.unmodifiable(_tracks.values);

  /// How much space the downloaded audio takes up.
  int get totalBytes => _sizes.values.fold(0, (sum, bytes) => sum + bytes);

  bool contains(String id) => _tracks.containsKey(id);

  /// The on-device file for [id], or null when it has not been downloaded.
  String? localPathFor(String id) => _tracks[id] == null ? null : _paths[id];

  /// How far a download in progress has got, from 0 to 1, or null when there is
  /// no download running for [id].
  double? progressFor(String id) => _progress[id];

  /// The message from the last failed download of [id], cleared when it is
  /// retried or removed.
  String? errorFor(String id) => _errors[id];

  bool isDownloading(String id) => _progress.containsKey(id);

  /// True when [id] is downloading but the server has not supplied a total size.
  bool isProgressIndeterminate(String id) =>
      _indeterminateProgress.contains(id);

  /// How many downloads are running at once.
  int get activeDownloadCount => _progress.length;

  /// Bytes received so far by all running downloads.
  int get activeBytes =>
      _receivedBytes.values.fold(0, (sum, bytes) => sum + bytes);

  /// Whether a sequential batch download is in progress.
  bool get isBatchRunning => _batchRunning;

  /// One-based position of the track currently being fetched by a batch.
  int? get batchPosition => _batchPosition;

  /// Number of tracks the current batch needed to fetch when it started.
  int? get batchTotal => _batchTotal;

  /// Whether the current batch includes any track from [trackIds]. This keeps a
  /// collection from displaying progress for a different collection's batch.
  bool isBatchRunningFor(Iterable<String> trackIds) =>
      _batchRunning && trackIds.any(_batchTrackIds.contains);

  /// Reads the stored downloads back, dropping any whose audio file has gone
  /// (cleared app data, or deleted by hand) so the list never offers a track
  /// that cannot be played.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefsKey) ?? const [];
    for (final entry in stored) {
      final decoded = _decodeEntry(entry);
      if (decoded == null) continue;
      final (track, size, path) = decoded;
      if (track == null || path == null) continue;
      if (!await File(path).exists()) continue;
      _tracks[track.id] = track;
      _sizes[track.id] = size;
      _paths[track.id] = path;
    }
    _ready = true;
    if (_changedWhileLoading) {
      _changedWhileLoading = false;
      await _save();
    }
    notifyListeners();
  }

  /// Downloads [track] so it can be played without a connection.
  ///
  /// A track that is already downloaded, or already downloading, is left alone.
  /// A failure is recorded against the track instead of thrown, so the UI can
  /// show it on the row that failed rather than crashing the whole list.
  Future<void> download(MediaItem track) async {
    final id = track.id;
    if (contains(id) || isDownloading(id)) return;
    final url = track.extras?['url'] as String?;
    if (url == null || url.isEmpty) {
      _errors[id] = 'This track has no audio to download.';
      notifyListeners();
      return;
    }

    _errors.remove(id);
    _progress[id] = 0;
    _receivedBytes[id] = 0;
    _indeterminateProgress.add(id);
    notifyListeners();

    File? target;
    try {
      final dir = await _directory();
      target = File('${dir.path}/${_fileNameFor(track)}');
      await target.parent.create(recursive: true);
      final bytes = await _fetch(url, target.path, (received, total) {
        _receivedBytes[id] = received;
        if (total > 0) {
          _indeterminateProgress.remove(id);
          _progress[id] = (received / total).clamp(0.0, 1.0).toDouble();
        } else {
          _indeterminateProgress.add(id);
          _progress[id] = 0;
        }
        notifyListeners();
      });
      _tracks[id] = track;
      _sizes[id] = bytes;
      _paths[id] = target.path;
      _changed();
    } catch (error) {
      // A half written file would be offered as a download that cannot play, so
      // it is removed before the failure is recorded.
      await _deleteQuietly(target);
      _errors[id] = _messageFor(error);
    } finally {
      _progress.remove(id);
      _receivedBytes.remove(id);
      _indeterminateProgress.remove(id);
      notifyListeners();
    }
  }

  /// Downloads each of [tracks] one after another.
  ///
  /// Sequential on purpose: several large downloads at once is what makes a
  /// phone run hot and drain its battery, and the list is usually short. Only
  /// one batch can run at a time, and an individual download must finish before
  /// a batch starts, so fetches never interleave.
  Future<void> downloadAll(List<MediaItem> tracks) async {
    if (_batchRunning || _progress.isNotEmpty) return;
    final pending = [
      for (final track in tracks)
        if (!contains(track.id) && !isDownloading(track.id)) track,
    ];
    if (pending.isEmpty) return;

    _batchRunning = true;
    _batchTrackIds = {for (final track in pending) track.id};
    _batchPosition = 1;
    _batchTotal = pending.length;
    notifyListeners();

    try {
      for (var index = 0; index < pending.length; index++) {
        _batchPosition = index + 1;
        notifyListeners();
        await download(pending[index]);
      }
    } finally {
      _batchRunning = false;
      _batchPosition = null;
      _batchTotal = null;
      _batchTrackIds = const {};
      notifyListeners();
    }
  }

  /// Drops the on-device copy of [id] and deletes its file.
  Future<void> remove(String id) async {
    if (!_tracks.containsKey(id)) return;
    final path = _paths.remove(id);
    _tracks.remove(id);
    _sizes.remove(id);
    _errors.remove(id);
    _changed();
    await _deleteQuietly(path == null ? null : File(path));
  }

  /// Removes every download and deletes the files.
  Future<void> clear() async {
    if (_tracks.isEmpty) return;
    final paths = [for (final path in _paths.values) File(path)];
    _tracks.clear();
    _sizes.clear();
    _paths.clear();
    _errors.clear();
    _changed();
    for (final file in paths) {
      await _deleteQuietly(file);
    }
  }

  /// Turns a track id into a file name. Ids are opaque hashes, so anything
  /// that is not a plain word character is replaced rather than trusted as a
  /// path segment.
  String _fileNameFor(MediaItem track) {
    final safe = track.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '${safe.isEmpty ? 'track' : safe}.mp3';
  }

  Future<void> _deleteQuietly(File? file) async {
    if (file == null) return;
    try {
      await file.delete();
    } catch (_) {
      // A file the app cannot delete is not worth failing the action over; it
      // is simply gone from the list and is ignored when the list is read back.
    }
  }

  /// A message worth showing for [error], rather than its type name.
  String _messageFor(Object error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      if (code == 401 || code == 403) {
        return 'The audio link has expired. Try again later.';
      }
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout) {
        return 'No connection. Check your network and try again.';
      }
    }
    return 'Download failed. Try again.';
  }

  /// Persists the current list. Kept out of the notify path so a failed write
  /// cannot leave the UI showing a download that was not stored.
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, [
      for (final entry in _tracks.entries)
        jsonEncode({
          'track': encodeTrack(entry.value),
          'bytes': _sizes[entry.key] ?? 0,
          'path': _paths[entry.key],
        }),
    ]);
  }

  void _changed() {
    notifyListeners();
    // A download that finishes while the stored list is still being read back
    // applies to the in-memory list, and is written out once loading is done.
    if (_ready) {
      unawaited(_save());
    } else {
      _changedWhileLoading = true;
    }
  }

  /// Reads one stored entry. Any part of it that cannot be read drops the whole
  /// entry, so a half written record never becomes a track that cannot play.
  (MediaItem?, int, String?)? _decodeEntry(String value) {
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final track = decodeTrack(json['track'] as String);
      if (track == null) return null;
      return (track, json['bytes'] as int? ?? 0, json['path'] as String?);
    } catch (_) {
      return null;
    }
  }
}

/// The app's own folder for downloaded audio, which the OS clears only when the
/// app is removed. Music is not a cache: a cache could be emptied at any time
/// and silently break a track the user believes is available offline.
Future<Directory> _defaultDirectory() async =>
    Directory('${(await getApplicationSupportDirectory()).path}/downloads');

/// Streams [url] into the file at [path], so a large track never has to fit in
/// memory at once.
Future<int> _fetchToFile(
  String url,
  String path,
  DownloadProgress onProgress,
) async {
  final dio = Dio();
  final file = File(path);
  await dio.download(url, path, onReceiveProgress: onProgress);
  // Use the completed file as the source of truth. A server can omit or
  // misreport Content-Length, while the bytes on disk are the actual download.
  return file.length();
}
