import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/sonora_audio_handler.dart';
import 'recent_store.dart';

/// Starts [track] and records it in the history.
void playAndRemember(WidgetRef ref, MediaItem track, {List<MediaItem>? queue}) {
  ref.read(recentStoreProvider).add(track);
  // Queue replacement and track selection are one operation. Starting them as
  // separate fire-and-forget calls allowed a completion or retry in between to
  // move the queue index before the requested track had begun loading.
  unawaited(ref.read(audioHandlerProvider).playTrack(track, queue: queue));
}
