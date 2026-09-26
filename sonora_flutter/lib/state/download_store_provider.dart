import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/download_store.dart';

/// Tracks kept on the device, shared with the player so a downloaded track is
/// played from its own file rather than the network.
///
/// The real store is created in `main` and passed in, because the player has to
/// know where a track's audio is before the first load. The fallback keeps the
/// UI usable in a test or preview that only overrode the handler.
final downloadStoreProvider = Provider<DownloadStore>((ref) {
  final store = DownloadStore();
  unawaited(store.load());
  return store;
});
