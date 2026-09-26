import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/music_api.dart';
import '../../state/play_and_remember.dart';
import '../../state/recent_store.dart';
import '../collection/collection_view.dart';
import '../components/artwork.dart';
import '../components/common.dart';
import '../components/track_tile.dart';
import '../formatting.dart';
import '../library/history_view.dart';
import '../player/mini_player_bar.dart';
import '../shimmer.dart';
import '../sonora_theme.dart';

/// The greeting shown on the home top bar.
String greetingFor(DateTime time) {
  if (time.hour < 12) return 'Good morning';
  if (time.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Picks one track from [tracks] without changing the catalog order.
MediaItem pickRandomTrack(List<MediaItem> tracks, {math.Random? random}) {
  if (tracks.isEmpty) {
    throw ArgumentError.value(tracks, 'tracks', 'must not be empty');
  }
  return tracks[(random ?? math.Random()).nextInt(tracks.length)];
}

class _CatalogStatus extends StatelessWidget {
  const _CatalogStatus({required this.error, required this.onRetry});

  final bool error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (!error) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 42,
              color: SonoraColors.muted,
            ),
            const SizedBox(height: 14),
            const Text(
              'Could not load your music',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            const Text(
              'Check your connection and try again.',
              style: TextStyle(color: SonoraColors.muted),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        const SkeletonBox(width: 120, height: 18),
        const SizedBox(height: 28),
        const SkeletonBox(width: double.infinity, height: 172, radius: 10),
        const SizedBox(height: 30),
        const SkeletonBox(width: 150, height: 18),
        const SizedBox(height: 14),
        const SkeletonCollectionRail(),
        const SizedBox(height: 30),
        const SkeletonBox(width: 130, height: 18),
        const SizedBox(height: 14),
        const SkeletonCollectionRail(),
        const SizedBox(height: 30),
        const SkeletonBox(width: 150, height: 18),
        const SizedBox(height: 8),
        const SkeletonTrackList(count: 6),
      ],
    );
  }
}

class HomeView extends ConsumerWidget {
  const HomeView({super.key});

  void _openSection(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _SectionPage(
            title: title,
            subtitle: subtitle,
            children: children,
          ),
        ),
      ),
    );
  }

  void _openCollection(BuildContext context, MusicCollection collection) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CollectionView(collection: collection),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final tracks = catalog.value ?? const <MediaItem>[];
    final playlists =
        ref.watch(playlistsProvider).value ?? const <MusicCollection>[];
    final albums = ref.watch(albumsProvider).value ?? const <MusicCollection>[];
    final artists =
        ref.watch(artistsProvider).value ?? const <MusicCollection>[];
    final recent = ref.watch(recentStoreProvider);
    if (tracks.isEmpty) {
      // Nothing has arrived yet, which is the normal first seconds of a launch,
      // so the page shape is shown with shimmer rather than an empty message.
      // The error state only belongs on a request that actually failed.
      return catalog.hasError
          ? PageFrame(
              child: _CatalogStatus(
                error: true,
                onRetry: () => ref.invalidate(catalogProvider),
              ),
            )
          : const PageFrame(child: _HomeSkeleton());
    }
    return PageFrame(
      child: CustomScrollView(
        key: const PageStorageKey('home'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            sliver: SliverList.list(
              children: [
                const _TopBar(),
                const SizedBox(height: 28),
                _HeroMix(tracks: tracks),
                _RecentlyPlayed(store: recent),
                const SizedBox(height: 30),
                SectionHeader(
                  title: 'Featured playlists',
                  action: 'See all',
                  onAction: () => _openSection(
                    context,
                    title: 'Featured playlists',
                    subtitle: plural(playlists.length, 'playlist'),
                    children: [
                      CollectionGrid(
                        items: playlists,
                        onSelect: (item) => _openCollection(context, item),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _CollectionRail(
                  items: playlists,
                  onSelect: (item) => _openCollection(context, item),
                ),
                const SizedBox(height: 30),
                SectionHeader(
                  title: 'Popular albums',
                  action: 'See all',
                  onAction: () => _openSection(
                    context,
                    title: 'Popular albums',
                    subtitle: plural(albums.length, 'album'),
                    children: [
                      CollectionGrid(
                        items: albums,
                        onSelect: (item) => _openCollection(context, item),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _CollectionRail(
                  items: albums,
                  onSelect: (item) => _openCollection(context, item),
                ),
                const SizedBox(height: 30),
                SectionHeader(
                  title: 'Made for you',
                  action: 'See all',
                  onAction: () => _openSection(
                    context,
                    title: 'Made for you',
                    subtitle: plural(tracks.length, 'song'),
                    children: [
                      ...tracks.map(
                        (track) => TrackTile(track: track, queue: tracks),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ...tracks
                    .take(6)
                    .map((track) => TrackTile(track: track, queue: tracks)),
                const SizedBox(height: 30),
                SectionHeader(
                  title: 'Featured artists',
                  action: 'See all',
                  onAction: () => _openSection(
                    context,
                    title: 'Featured artists',
                    subtitle: plural(artists.length, 'artist'),
                    children: [
                      CollectionGrid(
                        items: artists,
                        circular: true,
                        onSelect: (item) => _openCollection(context, item),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _CollectionRail(
                  items: artists,
                  circular: true,
                  onSelect: (item) => _openCollection(context, item),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: SonoraColors.green,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.graphic_eq_rounded, color: Colors.black),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SONORA',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: SonoraColors.green,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                greetingFor(DateTime.now()),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const NavBackButton(),
      ],
    );
  }
}

class _HeroMix extends ConsumerStatefulWidget {
  const _HeroMix({required this.tracks});

  final List<MediaItem> tracks;

  @override
  ConsumerState<_HeroMix> createState() => _HeroMixState();
}

class _HeroMixState extends ConsumerState<_HeroMix> {
  late MediaItem _track;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _track = pickRandomTrack(widget.tracks);
  }

  @override
  void didUpdateWidget(covariant _HeroMix oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tracks.isEmpty) return;
    if (!widget.tracks.any((track) => track.id == _track.id)) {
      _track = pickRandomTrack(widget.tracks);
    }
  }

  void _shuffle() {
    if (widget.tracks.length < 2) return;
    final currentIndex = widget.tracks.indexWhere(
      (track) => track.id == _track.id,
    );
    final nextIndex = currentIndex < 0
        ? _random.nextInt(widget.tracks.length)
        : (currentIndex + 1 + _random.nextInt(widget.tracks.length - 1)) %
              widget.tracks.length;
    setState(() => _track = widget.tracks[nextIndex]);
  }

  String get _subtitle {
    final artist = _track.artist?.trim();
    final album = _track.album?.trim();
    return [
      if (artist != null && artist.isNotEmpty) artist,
      if (album != null && album.isNotEmpty) album,
    ].join('  •  ');
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.55,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Artwork(path: _track.artPath, fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0x28000000),
                    Color(0xE8000000),
                  ],
                  stops: [0.28, 0.56, 1],
                ),
              ),
            ),
            Positioned(
              top: 14,
              right: 14,
              child: IconButton.filledTonal(
                tooltip: 'Shuffle song',
                onPressed: widget.tracks.length > 1 ? _shuffle : null,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.shuffle_rounded, size: 20),
              ),
            ),
            Positioned(
              left: 20,
              right: 18,
              bottom: 18,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'RANDOM PICK',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: SonoraColors.green,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          _track.title,
                          key: const ValueKey('hero-track-title'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 32,
                            height: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          _subtitle.isEmpty ? 'Sonora' : _subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFD3D7D3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Play mix',
                    style: IconButton.styleFrom(
                      backgroundColor: SonoraColors.green,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(54, 54),
                    ),
                    onPressed: () => playAndRemember(ref, _track),
                    icon: const Icon(Icons.play_arrow_rounded, size: 30),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionRail extends StatelessWidget {
  const _CollectionRail({
    required this.items,
    this.circular = false,
    this.onSelect,
  });

  final List<MusicCollection> items;
  final bool circular;
  final ValueChanged<MusicCollection>? onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 202,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.isEmpty ? 4 : math.min(10, items.length),
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          if (items.isEmpty) {
            return const SizedBox(
              width: 144,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 144, height: 144),
                  SizedBox(height: 10),
                  SkeletonBox(width: 116, height: 14),
                  SizedBox(height: 7),
                  SkeletonBox(width: 82, height: 11),
                ],
              ),
            );
          }
          final item = items[index];
          return SizedBox(
            width: 144,
            child: CollectionCard(
              item: item,
              circular: circular,
              onTap: onSelect == null ? null : () => onSelect!(item),
            ),
          );
        },
      ),
    );
  }
}

/// A pushed page that shows every item of a home section.
class _SectionPage extends ConsumerWidget {
  const _SectionPage({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                                title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                subtitle,
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
                  sliver: SliverList.list(children: children),
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

class _RecentlyPlayed extends StatelessWidget {
  const _RecentlyPlayed({required this.store});

  final RecentStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.tracks.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 30),
            SectionHeader(
              title: 'Recently played',
              action: 'See all',
              onAction: () => showHistory(context),
            ),
            const SizedBox(height: 8),
            ...store.tracks
                .take(3)
                .map((track) => TrackTile(track: track, queue: store.tracks)),
          ],
        );
      },
    );
  }
}
