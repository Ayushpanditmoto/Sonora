import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player/media_item_codec.dart';

final recentStoreProvider = Provider<RecentStore>((ref) {
  final store = RecentStore();
  unawaited(store.load());
  return store;
});

/// Recently played tracks, restored from and saved to local storage.
class RecentStore extends ChangeNotifier {
  static const _prefsKey = 'sonora.recents';
  static const _maxTracks = 50;

  final List<MediaItem> _tracks = [];
  bool _ready = false;
  bool _changedWhileLoading = false;

  List<MediaItem> get tracks => List.unmodifiable(_tracks);

  /// Restores the saved tracks. Called once when the provider is created.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in prefs.getStringList(_prefsKey) ?? const <String>[]) {
      final track = decodeTrack(entry);
      if (track != null && !_tracks.any((item) => item.id == track.id)) {
        _tracks.add(track);
      }
    }
    if (_tracks.length > _maxTracks) {
      _tracks.removeRange(_maxTracks, _tracks.length);
    }
    _ready = true;
    notifyListeners();
    if (_changedWhileLoading) await _save();
  }

  /// Puts [track] at the front of the history, moving it there rather than
  /// duplicating it so the same song never shows up twice.
  void add(MediaItem track) {
    _tracks.removeWhere((item) => item.id == track.id);
    _tracks.insert(0, track);
    if (_tracks.length > _maxTracks) _tracks.removeLast();
    _changed();
  }

  /// Drops a single track from the history.
  void remove(String id) {
    final before = _tracks.length;
    _tracks.removeWhere((item) => item.id == id);
    if (_tracks.length == before) return;
    _changed();
  }

  /// Empties the history.
  void clear() {
    if (_tracks.isEmpty) return;
    _tracks.clear();
    _changed();
  }

  void _changed() {
    notifyListeners();
    // A tap that lands before the stored tracks are read back still applies to
    // the in-memory list, and is flushed once loading finishes.
    if (_ready) {
      unawaited(_save());
    } else {
      _changedWhileLoading = true;
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, [
      for (final track in _tracks) encodeTrack(track),
    ]);
  }
}
