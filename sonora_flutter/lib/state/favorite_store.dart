import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player/media_item_codec.dart';

final favoriteStoreProvider = Provider<FavoriteStore>((ref) {
  final store = FavoriteStore();
  unawaited(store.load());
  return store;
});

/// Liked songs, restored from and saved to local storage.
///
/// The whole track is kept rather than only its id, so a song liked from
/// search, an album or a playlist still appears under Saved tracks even though
/// it is not part of the home catalogue.
class FavoriteStore extends ChangeNotifier {
  static const _prefsKey = 'sonora.favorites';

  final Map<String, MediaItem> _tracks = {};
  bool _ready = false;
  bool _changedWhileLoading = false;

  bool contains(String id) => _tracks.containsKey(id);

  int get length => _tracks.length;

  /// The liked songs, most recently liked first.
  List<MediaItem> get tracks => _tracks.values.toList(growable: false);

  /// Restores the saved songs. Called once when the provider is created.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Merged rather than replaced so a tap that lands while the stored songs
    // are still loading is not lost.
    for (final entry in prefs.getStringList(_prefsKey) ?? const <String>[]) {
      final track = decodeTrack(entry);
      if (track != null) _tracks[track.id] = track;
    }
    _ready = true;
    notifyListeners();
    if (_changedWhileLoading) await _save();
  }

  /// Likes [track], or removes it when it is already liked.
  void toggle(MediaItem track) {
    if (_tracks.remove(track.id) == null) _tracks[track.id] = track;
    notifyListeners();
    if (_ready) {
      unawaited(_save());
    } else {
      _changedWhileLoading = true;
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, [
      // Sorted by id so the stored list is in a stable order between saves.
      for (final id in _tracks.keys.toList()..sort()) encodeTrack(_tracks[id]!),
    ]);
  }
}
