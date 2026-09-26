import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/sonora_audio_handler.dart';
import '../../services/download_store.dart';
import '../../state/download_store_provider.dart';
import '../../state/play_and_remember.dart';
import '../player/now_playing.dart';
import '../components/track_tile.dart';
import '../formatting.dart';
import '../sonora_theme.dart';
import 'library_view.dart';

/// The tracks kept on the device, which play without a connection.
class _DownloadsView extends ConsumerWidget {
  const _DownloadsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(downloadStoreProvider);
    final hasTrack = ref.watch(currentTrackProvider).value != null;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final tracks = store.tracks;
        final activeTracks = store.activeTracks;
        final hasActive = activeTracks.isNotEmpty;
        final hasAny = tracks.isNotEmpty || hasActive;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Back',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Downloads',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    hasAny
                                        ? [
                                            if (tracks.isNotEmpty)
                                              '${plural(tracks.length, 'track')} downloaded • ${formatSize(store.totalBytes)}',
                                            if (hasActive)
                                              '${plural(activeTracks.length, 'download')} in progress',
                                          ].join(' • ')
                                        : 'Nothing downloaded yet',
                                    style: const TextStyle(
                                      color: SonoraColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                      sliver: !hasAny
                          ? const SliverToBoxAdapter(child: _downloadsEmpty)
                          : SliverList.list(
                              children: [
                                if (hasActive) ...[
                                  ActiveDownloads(
                                    store: store,
                                    tracks: activeTracks,
                                    queue: tracks.isEmpty
                                        ? activeTracks
                                        : tracks,
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                if (tracks.isNotEmpty) ...[
                                  Row(
                                    children: [
                                      FilledButton.icon(
                                        onPressed: () => playAndRemember(
                                          ref,
                                          tracks.first,
                                          queue: tracks,
                                        ),
                                        icon: const Icon(
                                          Icons.play_arrow_rounded,
                                        ),
                                        label: const Text('Play all'),
                                      ),
                                      const Spacer(),
                                      TextButton.icon(
                                        onPressed: () =>
                                            _confirmClear(context, store),
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18,
                                        ),
                                        label: const Text('Clear'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ...tracks.map(
                                    (track) =>
                                        TrackTile(track: track, queue: tracks),
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          bottomNavigationBar: hasTrack
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(8, 4, 8, 4),
                  child: MiniPlayer(),
                )
              : null,
        );
      },
    );
  }

  static const _downloadsEmpty = Padding(
    padding: EdgeInsets.symmetric(vertical: 64),
    child: Column(
      children: [
        Icon(Icons.download_rounded, size: 40, color: SonoraColors.muted),
        SizedBox(height: 14),
        Text(
          'Tap the download icon on a track to keep it on this device.',
          textAlign: TextAlign.center,
          style: TextStyle(color: SonoraColors.muted),
        ),
      ],
    ),
  );

  /// Deleting the audio cannot be undone, so it is confirmed first.
  Future<void> _confirmClear(BuildContext context, DownloadStore store) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove all downloads?'),
        content: const Text(
          'The audio is deleted from this device. You can download it again '
          'when you have a connection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove all'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await store.clear();
  }
}

/// Opens the list of downloaded tracks.
void showDownloads(BuildContext context) {
  Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const _DownloadsView()));
}
