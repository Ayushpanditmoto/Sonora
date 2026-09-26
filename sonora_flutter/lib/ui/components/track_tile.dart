import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/download_store.dart';
import '../../state/download_store_provider.dart';
import '../../state/play_and_remember.dart';
import '../sonora_theme.dart';
import 'artwork.dart';

/// Deletes a download only after [context] has confirmed the action.
///
/// This is used by the row's explicit Remove control. A swipe is intentionally
/// not a delete gesture: the row remains until the user confirms here.
Future<void> removeDownload(
  BuildContext context,
  DownloadStore store,
  MediaItem track,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remove download?'),
      content: Text('Remove "${track.title}" from this device?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) await store.remove(track.id);
}

/// Formats the API's `playCount` without pretending it is a view count.
/// Returns null when the endpoint did not provide a usable value.
String? playCountText(MediaItem track) {
  final value = track.extras?['playCount'];
  final count = switch (value) {
    final num number when number.isFinite && number >= 0 => number.round(),
    final String text => int.tryParse(text),
    _ => null,
  };
  if (count == null) return null;
  if (count >= 1000000) {
    final millions = count / 1000000;
    return '${millions.toStringAsFixed(millions.truncateToDouble() == millions ? 0 : 1)}M plays';
  }
  if (count >= 1000) {
    final thousands = count / 1000;
    return '${thousands.toStringAsFixed(thousands.truncateToDouble() == thousands ? 0 : 1)}K plays';
  }
  return '$count plays';
}

class TrackTile extends ConsumerWidget {
  const TrackTile({required this.track, this.queue, super.key});

  final MediaItem track;

  /// The list this track belongs to. When set, playing it makes that list the
  /// playback queue.
  final List<MediaItem>? queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadStoreProvider);
    return SizedBox(
      height: 68,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => playAndRemember(ref, track, queue: queue),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                width: 50,
                height: 50,
                child: Artwork(path: track.artPath),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  _TrackSubtitle(store: downloads, track: track),
                ],
              ),
            ),
            if (playCountText(track) case final playCount?) ...[
              const SizedBox(width: 8),
              Semantics(
                key: ValueKey('track-plays-${track.id}'),
                label: playCount,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.headphones_rounded,
                      size: 13,
                      color: SonoraColors.muted,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      playCount,
                      style: const TextStyle(
                        fontSize: 10,
                        color: SonoraColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            DownloadButton(store: downloads, track: track),
            Text(
              formatDuration(track.duration ?? Duration.zero),
              style: const TextStyle(fontSize: 11, color: SonoraColors.muted),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

/// The normal song metadata, replaced by an actionable download error.

class _TrackSubtitle extends StatelessWidget {
  const _TrackSubtitle({required this.store, required this.track});

  final DownloadStore store;
  final MediaItem track;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final error = store.errorFor(track.id);
        final subtitle = Text(
          error ?? '${track.artist}  •  ${track.album}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: error == null ? SonoraColors.muted : SonoraColors.coral,
            fontWeight: error == null ? FontWeight.normal : FontWeight.w600,
          ),
        );
        return error == null
            ? subtitle
            : Tooltip(message: error, child: subtitle);
      },
    );
  }
}

/// Downloads a track, retries a failed download, or removes a completed one.
///
/// The state comes straight from the store, so a download started on one screen
/// (or from a collection's "Download all") is reflected here and on every other
/// copy of the row.

class DownloadButton extends StatelessWidget {
  const DownloadButton({required this.store, required this.track, super.key});

  final DownloadStore store;
  final MediaItem track;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final progress = store.progressFor(track.id);
        if (progress != null) {
          final indeterminate = store.isProgressIndeterminate(track.id);
          // The transfer cannot be interrupted instantly, so the row says what
          // is happening rather than pretending the stop already took effect.
          final cancelling = store.isCancelling(track.id);
          final message = cancelling
              ? 'Stopping…'
              : indeterminate
              ? 'Downloading'
              : 'Downloading ${(progress * 100).round()}%';
          final hint = cancelling
              ? 'Stopping this download'
              : 'Stop this download';
          return Tooltip(
            message: message,
            child: Semantics(
              label: message,
              hint: hint,
              liveRegion: true,
              button: true,
              onTapHint: hint,
              child: InkWell(
                // Tapping the spinner is the only affordance on a row that is
                // otherwise showing progress, so the whole target is the tap
                // area rather than the 16dp indicator itself.
                borderRadius: BorderRadius.circular(20),
                onTap: cancelling ? null : () => store.cancel(track.id),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: cancelling
                        ? const Icon(
                            Icons.stop_rounded,
                            size: 18,
                            color: SonoraColors.muted,
                          )
                        : SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              value: indeterminate ? null : progress,
                              strokeWidth: 2,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          );
        }
        if (store.contains(track.id)) {
          return IconButton(
            tooltip: 'Remove download',
            onPressed: () => unawaited(removeDownload(context, store, track)),
            icon: const Icon(
              Icons.download_done_rounded,
              size: 20,
              color: SonoraColors.green,
            ),
          );
        }
        final error = store.errorFor(track.id);
        if (error != null) {
          return IconButton(
            tooltip: 'Retry download',
            onPressed: () => unawaited(store.download(track)),
            icon: const Icon(
              Icons.error_outline_rounded,
              size: 20,
              color: SonoraColors.coral,
            ),
          );
        }
        return IconButton(
          tooltip: 'Download',
          onPressed: () => unawaited(store.download(track)),
          icon: const Icon(
            Icons.arrow_circle_down_outlined,
            size: 20,
            color: SonoraColors.muted,
          ),
        );
      },
    );
  }
}
