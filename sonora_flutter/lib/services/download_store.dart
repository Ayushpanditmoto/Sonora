import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player/media_item_codec.dart';
import 'download_notification.dart';
import 'track_source.dart';
import 'youtube_api.dart';

/// Reports bytes received and the total expected, where the total is -1 when the
/// server does not say.
typedef DownloadProgress = void Function(int received, int total);

/// Writes the bytes at [url] to [path], reporting progress along the way, and
/// returns how many bytes it wrote. Throws when the download fails.
///
/// [cancelToken] aborts the transfer when it is cancelled. It is optional so an
/// injected fetcher can ignore cancellation, but the store still treats the
/// result as cancelled when the token is set.
typedef DownloadFetcher = Future<int> Function(
  String url,
  String path,
  DownloadProgress onProgress, {
  CancelToken? cancelToken,
});

/// Downloads one known-length source as concurrent byte ranges. This avoids
/// the per-connection throttle Googlevideo applies to mobile downloads.
typedef SegmentedDownloadFetcher = Future<int> Function(
  String url,
  String path,
  int contentLength,
  DownloadProgress onProgress, {
  CancelToken? cancelToken,
});

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
    DownloadNotifier? notifier,
    ResolveTrackStream? resolveStream,
    SegmentedDownloadFetcher? segmentedFetcher,
  }) : _fetch = fetcher ?? _fetchToFile,
       _directory = directory ?? _defaultDirectory,
       _notifier = notifier ?? DownloadNotifier(),
       _resolveStream = resolveStream ?? TrackSourceResolver().resolve,
       _fetchSegments = segmentedFetcher ?? _fetchSegmentsToFile {
    // The notification's Cancel and Cancel all actions are answered here,
    // because this is where the transfer actually lives. A null id means the
    // user asked for every running download to stop.
    _notifier.onCancel = (id) => id == null ? cancelAll() : cancel(id);
  }

  /// Downloads recorded under this key are matched to a track by id, so it
  /// moves whenever the ids the catalogue hands out change shape.
  static const _prefsKey = 'sonora.downloads.v2';

  /// The key downloads were stored under while Sonora read the
  /// `saavn.sumit.co` proxy, which identified a track by number where
  /// JioSaavn uses an opaque token. Nothing recorded under it can be matched to
  /// a track any more, so it is read once to clean up the files and then
  /// dropped.
  static const _legacyPrefsKey = 'sonora.downloads';

  final DownloadFetcher _fetch;
  final Future<Directory> Function() _directory;
  final DownloadNotifier _notifier;
  final ResolveTrackStream _resolveStream;
  final SegmentedDownloadFetcher _fetchSegments;

  final _tracks = <String, MediaItem>{};
  final _activeTracks = <String, MediaItem>{};
  final _sizes = <String, int>{};
  final _progress = <String, double>{};
  final _errors = <String, String>{};
  final _paths = <String, String>{};

  // Network chunks can arrive far faster than a person can read a percentage.
  // Coalescing callbacks keeps a download from rebuilding every visible row and
  // progress indicator dozens of times per second.
  static const _progressNotificationInterval = Duration(milliseconds: 100);
  DateTime? _lastProgressNotificationAt;
  Timer? _progressNotificationTimer;

  /// Downloads whose server has not supplied a total size. Their ring stays
  /// indeterminate rather than presenting an inaccurate fraction.
  final _indeterminateProgress = <String>{};

  /// Bytes received so far by downloads that are still running.
  final _receivedBytes = <String, int>{};

  /// Aborts the transfer behind each running download.
  final _tokens = <String, CancelToken>{};

  /// Downloads the user has asked to stop. They stay listed until the fetch
  /// actually unwinds, so a row can show that it is stopping rather than
  /// vanishing while bytes are still on the wire.
  final _cancelledIds = <String>{};

  /// Set when every running download, and the batch feeding them, is abandoned.
  bool _batchCancelled = false;

  bool _batchRunning = false;
  int? _batchPosition;
  int? _batchTotal;
  Set<String> _batchTrackIds = const {};

  /// True once the stored downloads have been read back.
  bool _ready = false;

  /// Set when something changed before [load] finished, so the change is written
  /// out once the stored downloads have been merged in.
  bool _changedWhileLoading = false;

  /// The downloaded tracks, newest completed download first.
  ///
  /// The map is kept in completion order for persistence and migration, while
  /// the public list is reversed so the newest item is always the first row in
  /// both Downloads surfaces.
  List<MediaItem> get tracks =>
      List<MediaItem>.unmodifiable(_tracks.values.toList().reversed);

  /// Tracks currently being fetched. They are kept separate from [tracks] so a
  /// download can appear in the Downloads screen before its file is complete.
  List<MediaItem> get activeTracks => List.unmodifiable(_activeTracks.values);

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

  /// Whether [id] has been asked to stop and is still unwinding.
  bool isCancelling(String id) => _cancelledIds.contains(id);

  /// Whether anything is running that [cancelAll] would stop.
  bool get canCancelAll => _progress.isNotEmpty;

  /// Stops the download of [id], if one is running.
  ///
  /// The partial file is deleted and nothing is recorded against the track: a
  /// download the user stopped is a decision, not a failure to retry.
  void cancel(String id) {
    if (!_progress.containsKey(id)) return;
    _cancelledIds.add(id);
    _tokens[id]?.cancel('Cancelled');
    notifyListeners();
  }

  /// Stops every running download and abandons the batch feeding them, so the
  /// rest of the queue is not started afterwards.
  void cancelAll() {
    if (_progress.isEmpty) return;
    _batchCancelled = true;
    for (final id in _progress.keys.toList()) {
      _cancelledIds.add(id);
      _tokens[id]?.cancel('Cancelled');
    }
    notifyListeners();
  }

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
    await _discardLegacyDownloads(prefs);
    final stored = prefs.getStringList(_prefsKey) ?? const [];
    for (final entry in stored) {
      final decoded = _decodeEntry(entry);
      if (decoded == null) continue;
      final (track, size, path) = decoded;
      if (track == null || path == null) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      // A file can survive on disk while being unplayable, for example when a
      // download finished against a response that was not the media at all.
      // Keeping it would list a track that silently never plays, so it is
      // dropped here and the user can download the track again.
      if (!hasPlayableContainer(file)) {
        await _deleteQuietly(file);
        _changedWhileLoading = true;
        continue;
      }
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

  /// Removes the audio recorded under [_legacyPrefsKey] and forgets the key.
  ///
  /// Those entries can never be matched to a track again, but the files are
  /// still the app's own, and leaving them behind would quietly keep taking up
  /// the user's storage with nothing on screen referring to them.
  Future<void> _discardLegacyDownloads(SharedPreferences prefs) async {
    final legacy = prefs.getStringList(_legacyPrefsKey);
    if (legacy == null) return;
    for (final entry in legacy) {
      final path = _decodeEntry(entry)?.$3;
      if (path != null) await _deleteQuietly(File(path));
    }
    await prefs.remove(_legacyPrefsKey);
  }

  /// Downloads [track] so it can be played without a connection.
  ///
  /// A track that is already downloaded, or already downloading, is left alone.
  /// A failure is recorded against the track instead of thrown, so the UI can
  /// show it on the row that failed rather than crashing the whole list.
  Future<void> download(MediaItem track) async {
    final id = track.id;
    if (contains(id) || isDownloading(id)) return;
    if (!canResolveTrackSource(track)) {
      const message = 'This track has no audio to download.';
      _errors[id] = message;
      notifyListeners();
      unawaited(_notifier.failed(track, message));
      return;
    }

    _errors.remove(id);
    _activeTracks[id] = track;
    _progress[id] = 0;
    _receivedBytes[id] = 0;
    _indeterminateProgress.add(id);
    final cancelToken = CancelToken();
    _tokens[id] = cancelToken;
    _notifyProgress();
    unawaited(
      _notifier.start(
        track,
        batchPosition: _batchPosition,
        batchTotal: _batchTotal,
      ),
    );

    final notifierUpdateInterval = const Duration(milliseconds: 100);
    DateTime? lastNotifierUpdate;
    File? target;
    try {
      void updateProgress(int received, int total) {
        _receivedBytes[id] = received;
        if (total > 0) {
          _indeterminateProgress.remove(id);
          _progress[id] = (received / total).clamp(0.0, 1.0).toDouble();
        } else {
          _indeterminateProgress.add(id);
          _progress[id] = 0;
        }
        _notifyProgress();
        final now = DateTime.now();
        if (lastNotifierUpdate == null ||
            now.difference(lastNotifierUpdate!) >= notifierUpdateInterval) {
          lastNotifierUpdate = now;
          unawaited(
            _notifier.update(
              track,
              receivedBytes: received,
              totalBytes: total > 0 ? total : null,
              batchPosition: _batchPosition,
              batchTotal: _batchTotal,
            ),
          );
        }
      }

      int bytes = 0;
      for (var attempt = 0; attempt < 2; attempt++) {
        final source = await _resolveStream(track);
        target = File(
          '${(await _directory()).path}/${_fileNameFor(track, source.extension)}',
        );
        await target.parent.create(recursive: true);
        try {
          final contentLength = source.contentLength;
          bytes =
              isYouTubeTrack(track) &&
                  contentLength != null &&
                  contentLength > 0
              ? await _fetchSegments(
                  source.url.toString(),
                  target.path,
                  contentLength,
                  updateProgress,
                  cancelToken: cancelToken,
                )
              : await _fetch(
                  source.url.toString(),
                  target.path,
                  updateProgress,
                  cancelToken: cancelToken,
                );
          break;
        } catch (error) {
          if (!isYouTubeTrack(track) ||
              attempt > 0 ||
              !_isForbiddenMediaError(error)) {
            rethrow;
          }
          // A Googlevideo URL can be rejected before its first byte. Delete the
          // partial file and resolve a new URL, mirroring playback's 403 retry.
          await _deleteQuietly(target);
          target = null;
          _receivedBytes[id] = 0;
          _progress[id] = 0;
          _indeterminateProgress.add(id);
          _notifyProgress();
        }
      }
      final completedTarget = target;
      if (completedTarget == null) {
        throw StateError('The audio download ended without a file.');
      }
      // A fetcher that does not honour the token can still return a complete
      // file after the user asked to stop, so the result is dropped here rather
      // than saved.
      if (_cancelledIds.contains(id)) {
        await _deleteQuietly(completedTarget);
        unawaited(_notifier.cancelled(track));
        return;
      }
      // A response can arrive complete in length and still not be the media,
      // for example when a ranged request is answered with bytes from a
      // different part of the file. Such a download would be listed forever and
      // fail every time it is played, so it is rejected and the row stays
      // retryable.
      if (!hasPlayableContainer(completedTarget)) {
        throw const UnusableAudioDownloadError();
      }
      _tracks[id] = track;
      _sizes[id] = bytes;
      _paths[id] = completedTarget.path;
      _changed();
      unawaited(
        _notifier.complete(
          track,
          batchPosition: _batchPosition,
          batchTotal: _batchTotal,
        ),
      );
    } catch (error) {
      // A half written file would be offered as a download that cannot play, so
      // it is removed before the failure is recorded.
      await _deleteQuietly(target);
      if (_isCancellation(error) || _cancelledIds.contains(id)) {
        // Stopping a download is the user's choice, so it is not recorded as a
        // failure the row would offer to retry.
        unawaited(_notifier.cancelled(track));
      } else {
        final message = _messageFor(error);
        _errors[id] = message;
        unawaited(_notifier.failed(track, message));
      }
    } finally {
      _activeTracks.remove(id);
      _progress.remove(id);
      _receivedBytes.remove(id);
      _indeterminateProgress.remove(id);
      _tokens.remove(id);
      _cancelledIds.remove(id);
      _progressNotificationTimer?.cancel();
      _progressNotificationTimer = null;
      _lastProgressNotificationAt = null;
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
    _batchCancelled = false;
    notifyListeners();

    try {
      for (var index = 0; index < pending.length; index++) {
        if (_batchCancelled) break;
        _batchPosition = index + 1;
        notifyListeners();
        await download(pending[index]);
      }
    } finally {
      _batchRunning = false;
      _batchPosition = null;
      _batchTotal = null;
      _batchCancelled = false;
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

  /// Ids are opaque hashes, so anything that is not a plain word character is
  /// replaced rather than trusted as a path segment.
  String _fileNameFor(MediaItem track, String extension) {
    final safe = track.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final safeExtension = extension.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    return '${safe.isEmpty ? 'track' : safe}.'
        '${safeExtension.isEmpty ? 'mp3' : safeExtension}';
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

  bool _isForbiddenMediaError(Object error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      return code == 401 || code == 403;
    }
    return error is StateError && error.toString().contains('403');
  }

  /// Whether [error] is the abort a cancelled token raises, rather than a real
  /// failure worth showing on the row.
  bool _isCancellation(Object error) =>
      error is DioException && error.type == DioExceptionType.cancel;

  /// A message worth showing for [error], rather than its type name.
  String _messageFor(Object error) {
    if (error is TrackSourceResolutionException) return error.message;
    if (error is UnusableAudioDownloadError) {
      return 'The audio could not be saved. Please try again.';
    }
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

  /// Publishes progress at a readable rate while always keeping the getters
  /// above up to date. The final state is flushed by [download], so a short
  /// download never appears stuck behind a pending timer.
  void _notifyProgress() {
    final now = DateTime.now();
    final previous = _lastProgressNotificationAt;
    final elapsed = previous == null
        ? _progressNotificationInterval
        : now.difference(previous);
    if (elapsed >= _progressNotificationInterval) {
      _lastProgressNotificationAt = now;
      notifyListeners();
      return;
    }
    _progressNotificationTimer ??= Timer(
      _progressNotificationInterval - elapsed,
      () {
        _progressNotificationTimer = null;
        _lastProgressNotificationAt = DateTime.now();
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _progressNotificationTimer?.cancel();
    unawaited(_notifier.clear());
    super.dispose();
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
/// Raised when a download finished at its expected length but the bytes are not
/// a media container, so the file can never be played.
class UnusableAudioDownloadError implements Exception {
  const UnusableAudioDownloadError();
}

/// Whether [file] begins with a container signature ExoPlayer can open.
///
/// A download is only useful if the player can decode it, and a response can
/// arrive at the right length while holding bytes from elsewhere: a ranged
/// request answered with a displaced window, or a body that was never the
/// media. Those files carry no `ftyp` or `moov` box, and ExoPlayer rejects them
/// with `UnrecognizedInputFormatException`, so the header is checked before the
/// file is offered as a download.
///
/// The read is synchronous. It touches a single 16 byte block on a file that is
/// already in the page cache, and keeping it off the event loop means the check
/// cannot interleave with a download that is still settling.
bool hasPlayableContainer(File file) {
  try {
    final handle = file.openSync();
    try {
      final head = handle.readSync(16);
      if (head.length < 4) return false;
      // Matroska/WebM, Ogg, ID3-tagged MP3, FLAC and RIFF/WAVE all lead with a
      // fixed four byte signature.
      if (_startsWith(head, const [0x1a, 0x45, 0xdf, 0xa3])) return true;
      if (_startsWith(head, const [0x4f, 0x67, 0x67, 0x53])) return true;
      if (_startsWith(head, const [0x49, 0x44, 0x33])) return true;
      if (_startsWith(head, const [0x66, 0x4c, 0x61, 0x43])) return true;
      if (_startsWith(head, const [0x52, 0x49, 0x46, 0x46])) return true;
      // ISO base media, which covers the MP4 and M4A YouTube serves, begins
      // with a four byte box length followed by the `ftyp` box type.
      if (head.length >= 8 &&
          _startsWith(head.sublist(4), const [0x66, 0x74, 0x79, 0x70])) {
        return true;
      }
      // A bare MPEG audio frame starts with eleven set sync bits.
      return head[0] == 0xff && (head[1] & 0xe0) == 0xe0;
    } finally {
      handle.closeSync();
    }
  } on FileSystemException {
    return false;
  }
}

bool _startsWith(List<int> bytes, List<int> signature) {
  if (bytes.length < signature.length) return false;
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) return false;
  }
  return true;
}

Future<int> _fetchToFile(
  String url,
  String path,
  DownloadProgress onProgress, {
  CancelToken? cancelToken,
}) async {
  final dio = Dio();
  final file = File(path);
  await dio.download(
    url,
    path,
    options: Options(headers: headersForMediaUrl(Uri.parse(url))),
    onReceiveProgress: onProgress,
    cancelToken: cancelToken,
  );
  // Use the completed file as the source of truth. A server can omit or
  // misreport Content-Length, while the bytes on disk are the actual download.
  return file.length();
}

/// Downloads a known-length YouTube stream with four concurrent ranges.
///
/// Googlevideo can throttle each mobile connection to roughly real-time audio
/// speed. Four ranges retain the original file order by writing each response
/// at its own byte offset, and stream rather than buffering the whole track.
Future<int> _fetchSegmentsToFile(
  String url,
  String path,
  int contentLength,
  DownloadProgress onProgress, {
  CancelToken? cancelToken,
}) async {
  const minimumParallelSize = 1024 * 1024;
  const segmentCount = 4;
  if (contentLength < minimumParallelSize) {
    return _fetchToFile(url, path, onProgress, cancelToken: cancelToken);
  }

  final file = File(path);
  final initial = await file.open(mode: FileMode.write);
  await initial.setPosition(contentLength - 1);
  await initial.writeByte(0);
  await initial.close();

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 2),
      headers: headersForMediaUrl(Uri.parse(url)),
    ),
  );
  final segmentLength = (contentLength + segmentCount - 1) ~/ segmentCount;
  var received = 0;
  final segments = <({int start, int end})>[];
  for (var index = 0; index < segmentCount; index++) {
    final start = index * segmentLength;
    if (start >= contentLength) break;
    final candidateEnd = start + segmentLength - 1;
    segments.add((
      start: start,
      end: candidateEnd < contentLength - 1 ? candidateEnd : contentLength - 1,
    ));
  }

  await Future.wait([
    for (final segment in segments)
      _writeSegment(
        dio: dio,
        url: url,
        file: file,
        start: segment.start,
        end: segment.end,
        cancelToken: cancelToken,
        onBytes: (count) {
          received += count;
          onProgress(received, contentLength);
        },
      ),
  ]);
  return file.length();
}

Future<void> _writeSegment({
  required Dio dio,
  required String url,
  required File file,
  required int start,
  required int end,
  required void Function(int count) onBytes,
  CancelToken? cancelToken,
}) async {
  final response = await dio.get<ResponseBody>(
    url,
    options: Options(
      responseType: ResponseType.stream,
      headers: {'Range': 'bytes=$start-$end', 'Accept-Encoding': 'identity'},
    ),
    cancelToken: cancelToken,
  );
  final body = response.data;
  if (response.statusCode != 206 || body == null) {
    throw StateError('YouTube range request returned ${response.statusCode}.');
  }

  final output = await file.open(mode: FileMode.writeOnly);
  try {
    await output.setPosition(start);
    final expected = end - start + 1;
    var written = 0;
    await for (final chunk in body.stream) {
      // A segment can already be streaming when the token is cancelled, and Dio
      // only rejects the request it issued, so the copy stops here too. The
      // partial file is deleted by the caller.
      if (cancelToken?.isCancelled ?? false) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: url),
          reason: 'Cancelled',
        );
      }
      await output.writeFrom(chunk);
      written += chunk.length;
      onBytes(chunk.length);
    }
    if (written != expected) {
      throw StateError(
        'Incomplete YouTube range $start-$end: received $written of $expected.',
      );
    }
  } finally {
    await output.close();
  }
}
