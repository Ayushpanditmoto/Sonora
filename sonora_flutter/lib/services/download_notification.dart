import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The platform surface used to tell the user what a download is doing.
///
/// Android gets a normal, low-priority progress notification. The calls are
/// no-ops on platforms without a notification implementation so the download
/// store remains usable in tests and on iOS/web.
class DownloadNotifier {
  DownloadNotifier() {
    // The notification's Cancel and Cancel all actions are answered by Dart,
    // because that is where the transfer actually lives. The store installs
    // [onCancel] as it is constructed, which is before any download can exist.
    const MethodChannel(_channelName).setMethodCallHandler(_handleNativeCall);
  }

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Stops one download, or every running download when the id is null.
  void Function(String? id)? onCancel;

  Future<Object?> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'cancelDownload':
        final id = call.arguments;
        // A malformed argument is ignored rather than cast, because this runs
        // on the platform thread and a throw here would cancel nothing.
        if (id is String) onCancel?.call(id);
      case 'cancelAllDownloads':
        onCancel?.call(null);
      default:
        break;
    }
    return null;
  }

  Timer? _clearTimer;

  bool _permissionRequested = false;

  /// Native calls are serialized so a fast progress update cannot overtake the
  /// start call (or the completion call) and leave the notification stuck on an
  /// earlier state.
  final Set<String> _activeIds = <String>{};
  Future<void> _operations = Future<void>.value();

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _operations.then((_) => operation());
    _operations = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> start(
    MediaItem track, {
    int? batchPosition,
    int? batchTotal,
  }) async {
    if (!_supported) return;
    _activeIds.add(track.id);
    return _enqueue(() async {
      _clearTimer?.cancel();
      await _ensurePermission();
      await _send('start', {
        'id': track.id,
        'title': 'Downloading ${track.title}',
        'text': _batchText(batchPosition, batchTotal) ?? 'Starting download…',
        'progress': 0,
        'indeterminate': true,
        'ongoing': true,
        'autoCancel': false,
        'cancellable': true,
        'activeCount': _activeIds.length,
      });
    });
  }

  Future<void> update(
    MediaItem track, {
    required int receivedBytes,
    required int? totalBytes,
    int? batchPosition,
    int? batchTotal,
  }) async {
    if (!_supported) return;
    return _enqueue(() async {
      await _ensurePermission();
      final knownTotal = totalBytes != null && totalBytes > 0;
      final percent = knownTotal
          ? ((receivedBytes / totalBytes) * 100).round().clamp(0, 100)
          : 0;
      final progressText = knownTotal
          ? '$percent% • ${_formatBytes(receivedBytes)} of ${_formatBytes(totalBytes)}'
          : '${_formatBytes(receivedBytes)} received';
      final batchText = _batchText(batchPosition, batchTotal);
      final text = batchText == null
          ? progressText
          : '$batchText • $progressText';
      await _send('update', {
        'id': track.id,
        'title': 'Downloading ${track.title}',
        'text': text,
        'progress': percent,
        'indeterminate': !knownTotal,
        'ongoing': true,
        'autoCancel': false,
        'cancellable': true,
        'activeCount': _activeIds.length,
      });
    });
  }

  Future<void> complete(
    MediaItem track, {
    int? batchPosition,
    int? batchTotal,
  }) async {
    if (!_supported) return;
    return _enqueue(() async {
      await _send('complete', {
        'id': track.id,
        'title': 'Downloaded ${track.title}',
        'text':
            _batchText(batchPosition, batchTotal) ??
            'Saved for offline listening',
        'progress': 100,
        'indeterminate': false,
        'ongoing': false,
        'autoCancel': true,
      });
      _activeIds.remove(track.id);
      if (_activeIds.isEmpty) _scheduleClear();
    });
  }

  Future<void> failed(MediaItem track, String message) async {
    if (!_supported) return;
    return _enqueue(() async {
      await _send('failed', {
        'id': track.id,
        'title': 'Download failed',
        'text': '${track.title} • $message',
        'progress': 0,
        'indeterminate': false,
        'ongoing': false,
        'autoCancel': true,
        'cancellable': false,
      });
      _activeIds.remove(track.id);
      if (_activeIds.isEmpty) _scheduleClear();
    });
  }

  /// Reports that a download was stopped by the user rather than failing.
  ///
  /// It reuses the transient shape of [failed] so the progress bar is replaced
  /// by a plain confirmation that clears itself, and carries no Cancel action
  /// because there is nothing left to cancel.
  Future<void> cancelled(MediaItem track) async {
    if (!_supported) return;
    return _enqueue(() async {
      await _send('cancelled', {
        'id': track.id,
        'title': 'Download cancelled',
        'text': track.title,
        'progress': 0,
        'indeterminate': false,
        'ongoing': false,
        'autoCancel': true,
        'cancellable': false,
      });
      _activeIds.remove(track.id);
      if (_activeIds.isEmpty) _scheduleClear();
    });
  }

  Future<void> clear() async {
    _clearTimer?.cancel();
    _clearTimer = null;
    _activeIds.clear();
    if (!_supported) return;
    await _enqueue(() => _send('clear', const {}));
  }

  void _scheduleClear() {
    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(seconds: 4), () {
      _clearTimer = null;
      unawaited(clear());
    });
  }

  Future<void> _ensurePermission() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    try {
      await const MethodChannel(_channelName)
          .invokeMethod<void>('requestPermission');
    } on MissingPluginException {
      // A test or a platform without the native channel simply has no download
      // notification; the download itself must not be blocked by it.
    } on PlatformException {
      // Permission denial is handled by Android and the store keeps working.
    }
  }

  Future<void> _send(String method, Map<String, Object?> arguments) async {
    try {
      await const MethodChannel(_channelName)
          .invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // See [_ensurePermission].
    } on PlatformException {
      // A notification failure must never turn a successful download into a
      // failed one.
    }
  }

  static String? _batchText(int? position, int? total) {
    if (position == null || total == null || total <= 0) return null;
    return 'Track $position of $total';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static const _channelName = 'com.panditfx.sonora/downloads';
}
