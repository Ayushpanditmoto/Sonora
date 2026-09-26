import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/download_store.dart';
import '../../state/download_store_provider.dart';
import '../../state/favorite_store.dart';
import '../../state/play_and_remember.dart';
import '../../state/recent_store.dart';
import '../components/common.dart';
import '../components/track_tile.dart';
import '../formatting.dart';
import '../sonora_theme.dart';
import 'history_view.dart';

class LibraryView extends ConsumerStatefulWidget {
  const LibraryView({super.key});

  @override
  ConsumerState<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends ConsumerState<LibraryView> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: PageFrame(
        child: CustomScrollView(
          key: const PageStorageKey('library'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
              sliver: SliverList.list(
                children: [
                  Row(
                    children: [
                      const NavBackButton(),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Your library',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: () {},
                        tooltip: 'Add playlist',
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _LibraryTabs(
                    onSelected: (index) => setState(() => _tab = index),
                  ),
                  const SizedBox(height: 18),
                  switch (_tab) {
                    0 => const _DownloadsTab(),
                    1 => const _RecentlyPlayedTab(),
                    _ => const _LikedSongsTab(),
                  },
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryTabs extends StatelessWidget {
  const _LibraryTabs({required this.onSelected});

  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      onTap: onSelected,
      tabs: const [
        Tab(text: 'Downloads'),
        Tab(text: 'Recently played'),
        Tab(text: 'Liked songs'),
      ],
    );
  }
}

class _DownloadsTab extends ConsumerWidget {
  const _DownloadsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(downloadStoreProvider);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final tracks = store.tracks;
        final activeTracks = store.activeTracks;
        final hasActive = activeTracks.isNotEmpty;
        if (tracks.isEmpty && !hasActive) {
          return const LibraryEmpty(
            icon: Icons.download_rounded,
            message:
                'Tap the download icon on a track to keep it on this device.',
          );
        }
        if (tracks.isEmpty) {
          return ActiveDownloads(
            store: store,
            tracks: activeTracks,
            queue: activeTracks,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${plural(tracks.length, 'track')} • ${formatSize(store.totalBytes)}',
                    style: const TextStyle(color: SonoraColors.muted),
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      unawaited(_confirmDownloadClear(context, store)),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Clear'),
                ),
              ],
            ),
            if (hasActive) ...[
              const SizedBox(height: 10),
              ActiveDownloads(
                store: store,
                tracks: activeTracks,
                queue: tracks,
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () =>
                  playAndRemember(ref, tracks.first, queue: tracks),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play all'),
            ),
            const SizedBox(height: 12),
            ...tracks.map((track) => TrackTile(track: track, queue: tracks)),
          ],
        );
      },
    );
  }
}

class _RecentlyPlayedTab extends ConsumerWidget {
  const _RecentlyPlayedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(recentStoreProvider);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final tracks = store.tracks;
        if (tracks.isEmpty) {
          return const LibraryEmpty(
            icon: Icons.history_rounded,
            message: 'Songs you play will show up here.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${plural(tracks.length, 'track')} played',
                    style: const TextStyle(color: SonoraColors.muted),
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      unawaited(confirmHistoryClear(context, store)),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () =>
                  playAndRemember(ref, tracks.first, queue: tracks),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play history'),
            ),
            const SizedBox(height: 12),
            ...tracks.map(
              (track) => SwipeToRemove(
                key: ValueKey(track.id),
                onRemove: () => store.remove(track.id),
                child: TrackTile(track: track, queue: tracks),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LikedSongsTab extends ConsumerWidget {
  const _LikedSongsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(favoriteStoreProvider);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final tracks = store.tracks;
        if (tracks.isEmpty) {
          return const LibraryEmpty(
            icon: Icons.favorite_border_rounded,
            message: 'Open a track and tap the heart in the player to save it.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${plural(tracks.length, 'track')} saved',
              style: const TextStyle(color: SonoraColors.muted),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () =>
                  playAndRemember(ref, tracks.first, queue: tracks),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play liked songs'),
            ),
            const SizedBox(height: 12),
            ...tracks.map((track) => TrackTile(track: track, queue: tracks)),
          ],
        );
      },
    );
  }
}

/// The active part of the Downloads screen. It deliberately uses ordinary
/// rows, not [Dismissible]: a horizontal swipe must never remove a download
/// before the user has pressed the explicit Remove control and confirmed it.
class ActiveDownloads extends StatelessWidget {
  const ActiveDownloads({
    required this.store,
    required this.tracks,
    required this.queue,
    super.key,
  });

  final DownloadStore store;
  final List<MediaItem> tracks;
  final List<MediaItem> queue;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    final heading = tracks.length == 1
        ? 'Downloading ${tracks.first.title}'
        : 'Downloading ${tracks.length} tracks';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.downloading_rounded,
              size: 18,
              color: SonoraColors.green,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                heading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SonoraColors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${plural(tracks.length, 'download')} • ${formatSize(store.activeBytes)} received',
              style: const TextStyle(color: SonoraColors.muted, fontSize: 11),
            ),
            // Stopping a running download is only offered here rather than
            // confirmed, because unlike removing a finished one it throws work
            // away that the user can simply ask for again.
            if (store.canCancelAll) ...[
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: store.cancelAll,
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: const Text('Cancel all'),
                style: TextButton.styleFrom(
                  foregroundColor: SonoraColors.muted,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        ...tracks.map(
          (track) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TrackTile(track: track, queue: queue),
                Padding(
                  padding: const EdgeInsets.only(left: 62, right: 8),
                  child: _ActiveDownloadProgress(store: store, track: track),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActiveDownloadProgress extends StatelessWidget {
  const _ActiveDownloadProgress({required this.store, required this.track});

  final DownloadStore store;
  final MediaItem track;

  @override
  Widget build(BuildContext context) {
    final progress = store.progressFor(track.id);
    final indeterminate = store.isProgressIndeterminate(track.id);
    return Row(
      children: [
        Expanded(
          child: LinearProgressIndicator(
            value: indeterminate ? null : progress,
            minHeight: 2,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          indeterminate ? 'Preparing…' : '${(progress! * 100).round()}%',
          style: const TextStyle(
            color: SonoraColors.green,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

Future<void> _confirmDownloadClear(
  BuildContext context,
  DownloadStore store,
) async {
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
