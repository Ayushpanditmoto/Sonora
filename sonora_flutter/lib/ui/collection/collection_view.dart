import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/download_store.dart';

import 'dart:async';

import '../../services/music_api.dart';
import '../../state/download_store_provider.dart';
import '../../state/play_and_remember.dart';
import '../components/artwork.dart';
import '../components/track_tile.dart';
import '../formatting.dart';
import '../player/mini_player_bar.dart';
import '../sonora_theme.dart';

class CollectionCard extends StatelessWidget {
  const CollectionCard({
    required this.item,
    this.circular = false,
    this.onTap,
    super.key,
  });

  final MusicCollection item;
  final bool circular;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(circular ? 72 : 6),
            child: AspectRatio(
              aspectRatio: 1,
              child: Artwork(path: item.imageUrl),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            item.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: SonoraColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class CollectionGrid extends StatelessWidget {
  const CollectionGrid({
    required this.items,
    this.circular = false,
    this.onSelect,
    super.key,
  });

  final List<MusicCollection> items;
  final bool circular;
  final ValueChanged<MusicCollection>? onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisExtent: 232,
        crossAxisSpacing: 14,
        mainAxisSpacing: 18,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return CollectionCard(
          item: item,
          circular: circular,
          onTap: onSelect == null ? null : () => onSelect!(item),
        );
      },
    );
  }
}

/// A pushed page with every playable song of an album, playlist or artist.
class CollectionView extends ConsumerWidget {
  const CollectionView({required this.collection, super.key});

  final MusicCollection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (id: collection.id, kind: collection.kind);
    final request = ref.watch(collectionTracksProvider(key));
    final tracks = request.value ?? const <MediaItem>[];
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
                          child: Text(
                            collection.kind.name.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: SonoraColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            collection.kind == CollectionKind.artist ? 60 : 8,
                          ),
                          child: SizedBox.square(
                            dimension: 120,
                            child: Artwork(path: collection.imageUrl),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                collection.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                request.isLoading
                                    ? collection.subtitle
                                    : plural(tracks.length, 'song'),
                                style: const TextStyle(
                                  color: SonoraColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 14),
                              // Downloading a whole album or playlist is the
                              // reason the store works one track at a time, so
                              // the button hands it the whole list and lets it
                              // take its time rather than firing every fetch at
                              // once.
                              _DownloadAllButton(
                                store: ref.read(downloadStoreProvider),
                                tracks: tracks,
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: tracks.isEmpty
                                    ? null
                                    : () => playAndRemember(
                                        ref,
                                        tracks.first,
                                        queue: tracks,
                                      ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: SonoraColors.green,
                                  foregroundColor: Colors.black,
                                ),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Play all'),
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
                  sliver: SliverList.list(
                    children: [
                      if (request.isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (request.hasError)
                        _CollectionError(
                          label: collection.kind.name,
                          onRetry: () =>
                              ref.invalidate(collectionTracksProvider(key)),
                        )
                      else if (tracks.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Text(
                              'Nothing to play here yet.',
                              style: TextStyle(color: SonoraColors.muted),
                            ),
                          ),
                        )
                      else
                        ...tracks.map(
                          (track) => TrackTile(track: track, queue: tracks),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const MiniPlayerBar(),
    );
  }
}

/// Collection-wide download control. All state comes from [store], so progress
/// started here or elsewhere updates the button without a Riverpod invalidation.
class _DownloadAllButton extends StatelessWidget {
  const _DownloadAllButton({required this.store, required this.tracks});

  final DownloadStore store;
  final List<MediaItem> tracks;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final ids = [for (final track in tracks) track.id];
      final remaining = tracks
          .where((track) => !store.contains(track.id))
          .length;
      final failed = tracks
          .where((track) => store.errorFor(track.id) != null)
          .length;
      final batchRunning = store.isBatchRunningFor(ids);
      final canStart =
          tracks.isNotEmpty &&
          remaining > 0 &&
          !batchRunning &&
          store.activeDownloadCount == 0;

      final String label;
      final Widget icon;
      if (tracks.isEmpty) {
        label = 'Download all';
        icon = const Icon(Icons.download_rounded, size: 18);
      } else if (batchRunning) {
        final position = store.batchPosition ?? 1;
        final total = store.batchTotal ?? remaining;
        label = '$position of $total • $remaining left';
        icon = SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(
            value: total == 0 ? null : ((position - 1) / total).clamp(0.0, 1.0),
            strokeWidth: 2,
          ),
        );
      } else if (remaining == 0) {
        label = 'Downloaded';
        icon = const Icon(Icons.download_done_rounded, size: 18);
      } else if (failed == remaining) {
        label = 'Retry ${plural(failed, 'failed track')}';
        icon = const Icon(Icons.refresh_rounded, size: 18);
      } else if (remaining < tracks.length) {
        label = 'Download $remaining left';
        icon = const Icon(Icons.download_rounded, size: 18);
      } else {
        label = 'Download all';
        icon = const Icon(Icons.download_rounded, size: 18);
      }

      return OutlinedButton.icon(
        onPressed: canStart ? () => unawaited(store.downloadAll(tracks)) : null,
        icon: icon,
        label: Text(label),
      );
    },
  );
}

class _CollectionError extends StatelessWidget {
  const _CollectionError({required this.label, required this.onRetry});

  final String label;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 36,
            color: SonoraColors.muted,
          ),
          const SizedBox(height: 12),
          Text(
            'Could not load this $label.',
            style: const TextStyle(color: SonoraColors.muted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
