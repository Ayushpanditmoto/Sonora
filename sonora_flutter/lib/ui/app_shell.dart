import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/sonora_audio_handler.dart';
import '../services/download_store.dart';
import '../services/music_api.dart';
import '../services/youtube_api.dart';
import '../state/download_store_provider.dart';
import '../state/favorite_store.dart';
import '../state/play_and_remember.dart';
import '../state/recent_store.dart';
import 'components/artwork.dart';
import 'components/track_tile.dart';
import 'drawer/app_drawer.dart';
import 'formatting.dart';
import 'player/now_playing.dart';
import 'shimmer.dart';
import 'sonora_theme.dart';

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

class _DrawerButton extends StatelessWidget {
  const _DrawerButton();

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => IconButton.filledTonal(
        tooltip: 'Open menu',
        onPressed: Scaffold.of(context).openDrawer,
        style: IconButton.styleFrom(
          backgroundColor: SonoraColors.surfaceHigh,
          foregroundColor: SonoraColors.text,
        ),
        icon: const Icon(Icons.menu_rounded),
      ),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  void _selectTab(int index) {
    if (index == _index) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppDrawer(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
      ),
      body: IndexedStack(
        index: _index,
        children: [
          const HomeView(),
          SearchView(isActive: _index == 1),
          const LibraryView(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _PlaybackErrorBar(),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: MiniPlayer(),
          ),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _selectTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_rounded),
                selectedIcon: Icon(Icons.manage_search_rounded),
                label: 'Search',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: 'Library',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shows a playback failure, such as a stream that has expired, above the mini
/// player.
///
/// The handler reports these instead of throwing, because the UI starts playback
/// without awaiting it: an error raised there would otherwise appear as an
/// uncaught exception rather than anything the user can act on.
class _PlaybackErrorBar extends ConsumerStatefulWidget {
  const _PlaybackErrorBar();

  @override
  ConsumerState<_PlaybackErrorBar> createState() => _PlaybackErrorBarState();
}

class _PlaybackErrorBarState extends ConsumerState<_PlaybackErrorBar> {
  String? _message;

  @override
  Widget build(BuildContext context) {
    ref.listen(playbackErrorProvider, (_, next) {
      final message = next.value;
      if (message == null || message == _message) return;
      setState(() => _message = message);
    });
    final message = _message;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
      child: Material(
        color: const Color(0xFF3A1D1D),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 18,
                color: Color(0xFFFF9B9B),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFFFD6D6),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _message = null),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: SonoraColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: child,
        ),
      ),
    );
  }
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

/// A row of shimmer cards in place of a collection rail.
class SkeletonCollectionRail extends StatelessWidget {
  const SkeletonCollectionRail({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 202,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, _) => const SizedBox(
          width: 144,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 144, height: 144, radius: 6),
              SizedBox(height: 10),
              SkeletonBox(width: 116, height: 14),
              SizedBox(height: 7),
              SkeletonBox(width: 82, height: 11),
            ],
          ),
        ),
      ),
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
          builder: (_) => _CollectionView(collection: collection),
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
                _SectionHeader(
                  title: 'Featured playlists',
                  action: 'See all',
                  onAction: () => _openSection(
                    context,
                    title: 'Featured playlists',
                    subtitle: plural(playlists.length, 'playlist'),
                    children: [
                      _CollectionGrid(
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
                _SectionHeader(
                  title: 'Popular albums',
                  action: 'See all',
                  onAction: () => _openSection(
                    context,
                    title: 'Popular albums',
                    subtitle: plural(albums.length, 'album'),
                    children: [
                      _CollectionGrid(
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
                _SectionHeader(
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
                _SectionHeader(
                  title: 'Featured artists',
                  action: 'See all',
                  onAction: () => _openSection(
                    context,
                    title: 'Featured artists',
                    subtitle: plural(artists.length, 'artist'),
                    children: [
                      _CollectionGrid(
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
        const _DrawerButton(),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (action != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Text(
                    action!,
                    style: const TextStyle(
                      color: SonoraColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: SonoraColors.muted,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.item,
    this.circular = false,
    this.onTap,
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
            child: _CollectionCard(
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

class _CollectionGrid extends StatelessWidget {
  const _CollectionGrid({
    required this.items,
    this.circular = false,
    this.onSelect,
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
        return _CollectionCard(
          item: item,
          circular: circular,
          onTap: onSelect == null ? null : () => onSelect!(item),
        );
      },
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
    final hasTrack = ref.watch(currentTrackProvider).value != null;
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
      bottomNavigationBar: hasTrack
          ? const Padding(
              padding: EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: MiniPlayer(),
            )
          : null,
    );
  }
}

/// A pushed page with every playable song of an album, playlist or artist.
class _CollectionView extends ConsumerWidget {
  const _CollectionView({required this.collection});

  final MusicCollection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (id: collection.id, kind: collection.kind);
    final request = ref.watch(collectionTracksProvider(key));
    final tracks = request.value ?? const <MediaItem>[];
    final hasTrack = ref.watch(currentTrackProvider).value != null;
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
      bottomNavigationBar: hasTrack
          ? const Padding(
              padding: EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: MiniPlayer(),
            )
          : null,
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
            _SectionHeader(
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

/// Opens the full play history, which is restored from local storage.
void showHistory(BuildContext context) {
  unawaited(
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => const _HistoryView())),
  );
}

/// Everything played so far, newest first, kept on the device between launches.
class _HistoryView extends ConsumerWidget {
  const _HistoryView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(recentStoreProvider);
    final hasTrack = ref.watch(currentTrackProvider).value != null;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final tracks = store.tracks;
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
                                    'History',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    tracks.isEmpty
                                        ? 'Nothing played yet'
                                        : '${plural(tracks.length, 'track')} played',
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
                      sliver: tracks.isEmpty
                          ? const SliverToBoxAdapter(child: _historyEmpty)
                          : SliverList.list(
                              children: [
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
                                      label: const Text('Play history'),
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
                                  (track) => _SwipeToRemove(
                                    // A stable key lets a swiped row be taken
                                    // out of the list without disturbing the
                                    // rows around it.
                                    key: ValueKey(track.id),
                                    onRemove: () => store.remove(track.id),
                                    child: TrackTile(
                                      track: track,
                                      queue: tracks,
                                    ),
                                  ),
                                ),
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

  static const _historyEmpty = Padding(
    padding: EdgeInsets.symmetric(vertical: 64),
    child: Column(
      children: [
        Icon(Icons.history_rounded, size: 40, color: SonoraColors.muted),
        SizedBox(height: 14),
        Text(
          'Songs you play will show up here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: SonoraColors.muted),
        ),
      ],
    ),
  );

  Future<void> _confirmClear(BuildContext context, RecentStore store) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'This removes every recently played track from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) store.clear();
  }
}

/// A failed inline request (a search, a collection) with a retry right where the
/// content would have been, rather than taking over the whole screen.
class _InlineRetry extends StatelessWidget {
  const _InlineRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 28,
            color: SonoraColors.muted,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: SonoraColors.muted),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class SearchView extends ConsumerStatefulWidget {
  const SearchView({super.key, this.isActive = true});

  final bool isActive;

  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView> {
  String query = '';
  Timer? _debounce;
  int _resultTab = 0;
  final FocusNode _searchFocus = FocusNode();

  @override
  void didUpdateWidget(covariant SearchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      _searchFocus.unfocus();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocus.unfocus();
    _searchFocus.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    final next = value.trim();
    if (next.isEmpty) {
      setState(() => query = '');
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => setState(() => query = next),
    );
  }

  void _openCollection(MusicCollection collection) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _CollectionView(collection: collection),
        ),
      ),
    );
  }

  Widget _songResults(AsyncValue<List<MediaItem>> request) {
    if (request.isLoading) return const _SearchSkeletonSection();
    if (request.hasError) {
      return _SearchErrorSection(
        title: 'Songs',
        onRetry: () => ref.invalidate(searchResultsProvider(query)),
      );
    }
    final tracks = request.value ?? const <MediaItem>[];
    if (tracks.isEmpty) return const _SearchCategoryEmpty(title: 'Songs');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Songs'),
        const SizedBox(height: 8),
        ...tracks.map((track) => TrackTile(track: track, queue: tracks)),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _youtubeResults(AsyncValue<List<MediaItem>> request) {
    if (request.isLoading) return const _SearchSkeletonSection();
    if (request.hasError) {
      return _SearchErrorSection(
        title: 'YouTube',
        onRetry: () => ref.invalidate(youtubeSearchResultsProvider(query)),
      );
    }
    final tracks = request.value ?? const <MediaItem>[];
    if (tracks.isEmpty) {
      return const _SearchCategoryEmpty(title: 'YouTube videos');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'YouTube'),
        const SizedBox(height: 4),
        const Text(
          'Download only videos you own or have permission to save.',
          style: TextStyle(fontSize: 11, color: SonoraColors.muted),
        ),
        const SizedBox(height: 10),
        ...tracks.map((track) => TrackTile(track: track, queue: tracks)),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _collectionResults(
    String title,
    CollectionKind kind,
    AsyncValue<List<MusicCollection>> request, {
    bool circular = false,
  }) {
    if (request.isLoading) {
      return const _SearchSkeletonSection(collection: true);
    }
    if (request.hasError) {
      return _SearchErrorSection(
        title: title,
        onRetry: () => ref.invalidate(
          searchCollectionsProvider((query: query, kind: kind)),
        ),
      );
    }
    final items = request.value ?? const <MusicCollection>[];
    if (items.isEmpty) return _SearchCategoryEmpty(title: title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: title),
        const SizedBox(height: 10),
        _CollectionGrid(
          items: items,
          circular: circular,
          onSelect: _openCollection,
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _selectedResults({
    required bool youtubeAvailable,
    required AsyncValue<List<MediaItem>>? songs,
    required AsyncValue<List<MusicCollection>>? albums,
    required AsyncValue<List<MusicCollection>>? artists,
    required AsyncValue<List<MusicCollection>>? playlists,
    required AsyncValue<List<MediaItem>>? youtube,
  }) {
    if (!youtubeAvailable) {
      return switch (_resultTab) {
        0 => _songResults(songs!),
        1 => _collectionResults('Albums', CollectionKind.album, albums!),
        2 => _collectionResults(
          'Artists',
          CollectionKind.artist,
          artists!,
          circular: true,
        ),
        _ => _collectionResults(
          'Playlists',
          CollectionKind.playlist,
          playlists!,
        ),
      };
    }
    return switch (_resultTab) {
      0 => _songResults(songs!),
      1 => _youtubeResults(youtube!),
      2 => _collectionResults('Albums', CollectionKind.album, albums!),
      3 => _collectionResults(
        'Artists',
        CollectionKind.artist,
        artists!,
        circular: true,
      ),
      _ => _collectionResults('Playlists', CollectionKind.playlist, playlists!),
    };
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = query.isNotEmpty;
    final youtubeAvailable = ref.watch(youtubeSearchAvailableProvider);
    final albumTab = youtubeAvailable ? 2 : 1;
    final artistTab = youtubeAvailable ? 3 : 2;
    final playlistTab = youtubeAvailable ? 4 : 3;
    final songs = hasQuery && _resultTab == 0
        ? ref.watch(searchResultsProvider(query))
        : null;
    final youtube = hasQuery && youtubeAvailable && _resultTab == 1
        ? ref.watch(youtubeSearchResultsProvider(query))
        : null;
    final albums = hasQuery && _resultTab == albumTab
        ? ref.watch(
            searchCollectionsProvider((
              query: query,
              kind: CollectionKind.album,
            )),
          )
        : null;
    final artists = hasQuery && _resultTab == artistTab
        ? ref.watch(
            searchCollectionsProvider((
              query: query,
              kind: CollectionKind.artist,
            )),
          )
        : null;
    final playlists = hasQuery && _resultTab == playlistTab
        ? ref.watch(
            searchCollectionsProvider((
              query: query,
              kind: CollectionKind.playlist,
            )),
          )
        : null;
    final selectedRequest = youtubeAvailable
        ? switch (_resultTab) {
            0 => songs,
            1 => youtube,
            2 => albums,
            3 => artists,
            _ => playlists,
          }
        : switch (_resultTab) {
            0 => songs,
            1 => albums,
            2 => artists,
            _ => playlists,
          };
    final allSettled =
        hasQuery &&
        selectedRequest?.isLoading == false &&
        selectedRequest?.hasError != true;
    final hasResults = selectedRequest?.value?.isNotEmpty ?? false;
    final noResultName = youtubeAvailable
        ? switch (_resultTab) {
            0 => 'songs',
            1 => 'YouTube videos',
            2 => 'albums',
            3 => 'artists',
            _ => 'playlists',
          }
        : switch (_resultTab) {
            0 => 'songs',
            1 => 'albums',
            2 => 'artists',
            _ => 'playlists',
          };

    return DefaultTabController(
      length: youtubeAvailable ? 5 : 4,
      child: PageFrame(
        child: CustomScrollView(
          key: const PageStorageKey('search'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
              sliver: SliverList.list(
                children: [
                  Row(
                    children: [
                      const _DrawerButton(),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Search Sonora',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    onChanged: _search,
                    decoration: InputDecoration(
                      hintText: youtubeAvailable
                          ? 'Songs, YouTube, albums, artists, playlists'
                          : 'Songs, albums, artists, playlists',
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (!hasQuery)
                    _SearchPrompt(showYouTube: youtubeAvailable)
                  else ...[
                    _SearchTabs(
                      showYouTube: youtubeAvailable,
                      onSelected: (index) => setState(() => _resultTab = index),
                    ),
                    const SizedBox(height: 16),
                    if (allSettled && !hasResults)
                      _NoSearchResults(itemName: noResultName)
                    else
                      _selectedResults(
                        youtubeAvailable: youtubeAvailable,
                        songs: songs,
                        albums: albums,
                        artists: artists,
                        playlists: playlists,
                        youtube: youtube,
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPrompt extends StatelessWidget {
  const _SearchPrompt({required this.showYouTube});

  final bool showYouTube;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 72),
      child: Column(
        children: [
          const Icon(Icons.search_rounded, size: 40, color: SonoraColors.muted),
          const SizedBox(height: 14),
          Text(
            showYouTube ? 'Search songs and YouTube' : 'Search songs',
            textAlign: TextAlign.center,
            style: TextStyle(color: SonoraColors.muted),
          ),
        ],
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults({required this.itemName});

  final String itemName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 72),
      child: Center(
        child: Text(
          'No $itemName found. Try a different search.',
          style: TextStyle(color: SonoraColors.muted),
        ),
      ),
    );
  }
}

class _SearchTabs extends StatelessWidget {
  const _SearchTabs({required this.onSelected, this.showYouTube = false});

  final bool showYouTube;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      onTap: onSelected,
      tabs: [
        const Tab(text: 'Songs'),
        if (showYouTube) const Tab(text: 'YouTube'),
        const Tab(text: 'Albums'),
        const Tab(text: 'Artists'),
        const Tab(text: 'Playlists'),
      ],
    );
  }
}

class _SearchCategoryEmpty extends StatelessWidget {
  const _SearchCategoryEmpty({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Center(
        child: Text(
          'No ${title.toLowerCase()} found for this search.',
          style: const TextStyle(color: SonoraColors.muted),
        ),
      ),
    );
  }
}

class _SearchSkeletonSection extends StatelessWidget {
  const _SearchSkeletonSection({this.collection = false});

  final bool collection;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkeletonBox(width: 110, height: 20),
        const SizedBox(height: 12),
        if (collection)
          const SkeletonCollectionRail()
        else
          const SkeletonTrackList(count: 4),
        const SizedBox(height: 28),
      ],
    );
  }
}

class _SearchErrorSection extends StatelessWidget {
  const _SearchErrorSection({required this.title, required this.onRetry});

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: title),
        _InlineRetry(
          message:
              'Could not load $title. Check your connection and try again.',
          onRetry: onRetry,
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

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
                      const _DrawerButton(),
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
          return const _LibraryEmpty(
            icon: Icons.download_rounded,
            message:
                'Tap the download icon on a track to keep it on this device.',
          );
        }
        if (tracks.isEmpty) {
          return _ActiveDownloads(
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
              _ActiveDownloads(
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
          return const _LibraryEmpty(
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
                      unawaited(_confirmHistoryClear(context, store)),
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
              (track) => _SwipeToRemove(
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
          return const _LibraryEmpty(
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

class _LibraryEmpty extends StatelessWidget {
  const _LibraryEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Icon(icon, size: 40, color: SonoraColors.muted),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: SonoraColors.muted),
          ),
        ],
      ),
    );
  }
}

/// The active part of the Downloads screen. It deliberately uses ordinary
/// rows, not [Dismissible]: a horizontal swipe must never remove a download
/// before the user has pressed the explicit Remove control and confirmed it.
class _ActiveDownloads extends StatelessWidget {
  const _ActiveDownloads({
    required this.store,
    required this.tracks,
    required this.queue,
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

/// Swipes a row away to remove a single item, like clearing one track from the
/// history without wiping the rest of it.
class _SwipeToRemove extends StatelessWidget {
  const _SwipeToRemove({
    required this.onRemove,
    required this.child,
    super.key,
  });

  final VoidCallback onRemove;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: key!,
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: const ColoredBox(
        color: Colors.red,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: 20),
            child: Icon(Icons.delete_outline_rounded, color: Colors.white),
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Deletes a download only after [context] has confirmed the action.
///
/// This is used by the row's explicit Remove control. A swipe is intentionally
/// not a delete gesture: the row remains until the user confirms here.

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

Future<void> _confirmHistoryClear(
  BuildContext context,
  RecentStore store,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Clear history?'),
      content: const Text(
        'This removes every recently played track from this device.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Clear'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) store.clear();
}

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
                                  _ActiveDownloads(
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

/// Bytes in a form worth reading: downloads are usually megabytes, and the
/// exact count matters less than which unit it is in.
void showDownloads(BuildContext context) {
  Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const _DownloadsView()));
}

/// Formats the API's `playCount` without pretending it is a view count.
/// Returns null when the endpoint did not provide a usable value.
