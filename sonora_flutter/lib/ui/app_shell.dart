import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player/media_item_codec.dart';
import '../player/sonora_audio_handler.dart';
import '../services/download_store.dart';
import '../services/music_api.dart';
import 'shimmer.dart';
import 'sonora_theme.dart';

const moodNames = ['Focus', 'Night drive', 'Fresh finds', 'Unwind'];

/// The greeting shown on the home top bar.
String greetingFor(DateTime time) {
  if (time.hour < 12) return 'Good morning';
  if (time.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

final favoriteStoreProvider = Provider<FavoriteStore>((ref) {
  final store = FavoriteStore();
  unawaited(store.load());
  return store;
});
final recentStoreProvider = Provider<RecentStore>((ref) {
  final store = RecentStore();
  unawaited(store.load());
  return store;
});

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

void playAndRemember(WidgetRef ref, MediaItem track, {List<MediaItem>? queue}) {
  ref.read(recentStoreProvider).add(track);
  final handler = ref.read(audioHandlerProvider);
  // Playing from a collection or a list replaces the queue, so next and
  // previous keep walking that list instead of the home catalogue.
  if (queue != null && queue.isNotEmpty) unawaited(handler.loadQueue(queue));
  // Fire and forget: playback interruptions are handled inside the handler.
  unawaited(handler.playTrack(track));
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [HomeView(), SearchView(), LibraryView()],
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
            onDestinationSelected: (value) => setState(() => _index = value),
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

String _plural(int count, String noun) =>
    '$count ${count == 1 ? noun : '${noun}s'}';

/// The home page while its sections are still loading: the same layout, with
/// the artwork and text replaced by shimmer.
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
                _HeroMix(track: tracks.first),
                _RecentlyPlayed(store: recent),
                const SizedBox(height: 30),
                _SectionHeader(
                  title: 'Featured playlists',
                  action: 'See all',
                  onAction: () => _openSection(
                    context,
                    title: 'Featured playlists',
                    subtitle: _plural(playlists.length, 'playlist'),
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
                    subtitle: _plural(albums.length, 'album'),
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
                    subtitle: _plural(tracks.length, 'song'),
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
                    subtitle: _plural(artists.length, 'artist'),
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
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SONORA',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: SonoraColors.green,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Good evening, Ayush',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Notifications',
          onPressed: () {},
          icon: const Icon(Icons.notifications_none_rounded, size: 21),
        ),
      ],
    );
  }
}

class _HeroMix extends ConsumerWidget {
  const _HeroMix({required this.track});

  final MediaItem track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AspectRatio(
      aspectRatio: 1.55,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Artwork(path: track.artPath, fit: BoxFit.cover),
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
              left: 20,
              right: 18,
              bottom: 18,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CURATED FOR TONIGHT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: SonoraColors.green,
                          ),
                        ),
                        SizedBox(height: 7),
                        Text(
                          'After dark',
                          style: TextStyle(
                            fontSize: 32,
                            height: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 7),
                        Text(
                          'Soft electronics and late-night pulse',
                          style: TextStyle(
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
                    onPressed: () => playAndRemember(ref, track),
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
                                    : _plural(tracks.length, 'song'),
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
        label = 'Retry ${_plural(failed, 'failed track')}';
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
                                        : '${_plural(tracks.length, 'track')} played',
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
  const SearchView({super.key});

  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView> {
  String query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
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

  @override
  Widget build(BuildContext context) {
    final popular = ref.watch(catalogProvider).value ?? const <MediaItem>[];
    final search = query.isEmpty
        ? null
        : ref.watch(searchResultsProvider(query));
    final results = search?.value ?? const <MediaItem>[];
    return PageFrame(
      child: CustomScrollView(
        key: const PageStorageKey('search'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
            sliver: SliverList.list(
              children: [
                Text(
                  'Find your sound',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 20),
                TextField(
                  onChanged: _search,
                  decoration: const InputDecoration(
                    hintText: 'Songs, artists, albums',
                    prefixIcon: Icon(Icons.search_rounded),
                    suffixIcon: Icon(Icons.tune_rounded),
                  ),
                ),
                const SizedBox(height: 28),
                if (query.isEmpty) ...[
                  const _SectionHeader(title: 'Browse moods'),
                  const SizedBox(height: 14),
                  const _MoodGrid(),
                  const SizedBox(height: 30),
                  const _SectionHeader(title: 'Popular searches'),
                  const SizedBox(height: 8),
                  ...popular
                      .take(5)
                      .map((track) => TrackTile(track: track, queue: popular)),
                ] else ...[
                  if (search?.isLoading == true)
                    const SkeletonTrackList()
                  else if (search?.hasError == true)
                    _InlineRetry(
                      message:
                          'Search failed. Check your connection and try again.',
                      onRetry: () =>
                          ref.invalidate(searchResultsProvider(query)),
                    )
                  else ...[
                    Text(
                      '${results.length} results',
                      style: const TextStyle(
                        color: SonoraColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (results.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 64),
                        child: Center(
                          child: Text(
                            'No music found. Try another mood.',
                            style: TextStyle(color: SonoraColors.muted),
                          ),
                        ),
                      )
                    else
                      ...results.map(
                        (track) => TrackTile(track: track, queue: results),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodGrid extends StatelessWidget {
  const _MoodGrid();

  static const colors = [
    SonoraColors.green,
    SonoraColors.coral,
    SonoraColors.lilac,
    Color(0xFFFFD66B),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 86,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: moodNames.length,
      itemBuilder: (context, index) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors[index].withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors[index].withValues(alpha: 0.32)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                moodNames[index],
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(
              [
                Icons.center_focus_strong_rounded,
                Icons.nightlight_round,
                Icons.auto_awesome_rounded,
                Icons.spa_outlined,
              ][index],
              color: colors[index],
            ),
          ],
        ),
      ),
    );
  }
}

class LibraryView extends ConsumerWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(favoriteStoreProvider);
    final recents = ref.watch(recentStoreProvider);

    return PageFrame(
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          // Straight from the store rather than filtered out of the home
          // catalogue, so a song saved from search, an album or a playlist is
          // still listed here.
          final liked = store.tracks;
          return CustomScrollView(
            key: const PageStorageKey('library'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
                sliver: SliverList.list(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Your library',
                            style: Theme.of(context).textTheme.displaySmall,
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
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: SonoraColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: SonoraColors.lilac,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: Colors.black,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Liked songs',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${liked.length} tracks',
                                  style: const TextStyle(
                                    color: SonoraColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: liked.isEmpty
                                ? null
                                : () => playAndRemember(
                                    ref,
                                    liked.first,
                                    queue: liked,
                                  ),
                            icon: const Icon(
                              Icons.play_circle_fill_rounded,
                              size: 38,
                              color: SonoraColors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _HistoryCard(store: recents),
                    const SizedBox(height: 14),
                    const _DownloadsCard(),
                    const SizedBox(height: 30),
                    const _SectionHeader(title: 'Saved tracks'),
                    const SizedBox(height: 8),
                    if (liked.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: Text(
                            'Tap the heart on a track to save it.',
                            style: TextStyle(color: SonoraColors.muted),
                          ),
                        ),
                      )
                    else
                      ...liked.map(
                        (track) => TrackTile(track: track, queue: liked),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
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
                                    tracks.isEmpty
                                        ? 'Nothing downloaded yet'
                                        : '${_plural(tracks.length, 'track')} • ${_formatSize(store.totalBytes)}',
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
                          ? const SliverToBoxAdapter(child: _downloadsEmpty)
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
                                  (track) => _SwipeToRemove(
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

/// A library shortcut to the tracks kept on the device.
class _DownloadsCard extends ConsumerWidget {
  const _DownloadsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(downloadStoreProvider);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final tracks = store.tracks;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showDownloads(context),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SonoraColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: SonoraColors.green,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.download_rounded,
                    color: Colors.black,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Downloads',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        tracks.isEmpty
                            ? 'Keep songs on this device'
                            : '${_plural(tracks.length, 'track')} • ${_formatSize(store.totalBytes)}',
                        style: const TextStyle(color: SonoraColors.muted),
                      ),
                      if (store.activeDownloadCount > 0) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${_plural(store.activeDownloadCount, 'download')} • ${_formatSize(store.activeBytes)} received',
                          style: const TextStyle(
                            color: SonoraColors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: tracks.isEmpty
                      ? null
                      : () => playAndRemember(ref, tracks.first, queue: tracks),
                  icon: const Icon(
                    Icons.play_circle_fill_rounded,
                    size: 38,
                    color: SonoraColors.green,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Bytes in a form worth reading: downloads are usually megabytes, and the
/// exact count matters less than which unit it is in.
String _formatSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Opens the list of downloaded tracks.
void showDownloads(BuildContext context) {
  Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const _DownloadsView()));
}

/// A library shortcut to the full play history.
class _HistoryCard extends ConsumerWidget {
  const _HistoryCard({required this.store});

  final RecentStore store;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final tracks = store.tracks;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showHistory(context),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SonoraColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: SonoraColors.green,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    color: Colors.black,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recently played',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        tracks.isEmpty
                            ? 'Nothing played yet'
                            : _plural(tracks.length, 'track'),
                        style: const TextStyle(color: SonoraColors.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: tracks.isEmpty
                      ? null
                      : () => playAndRemember(ref, tracks.first, queue: tracks),
                  icon: const Icon(
                    Icons.play_circle_fill_rounded,
                    size: 38,
                    color: SonoraColors.green,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class TrackTile extends ConsumerWidget {
  const TrackTile({required this.track, this.queue, super.key});

  final MediaItem track;

  /// The list this track belongs to. When set, playing it makes that list the
  /// playback queue.
  final List<MediaItem>? queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(favoriteStoreProvider);
    final downloads = ref.watch(downloadStoreProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([store, downloads]),
      builder: (context, _) => SizedBox(
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
              IconButton(
                tooltip: 'Save track',
                onPressed: () => store.toggle(track),
                icon: Icon(
                  store.contains(track.id)
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 20,
                  color: store.contains(track.id)
                      ? SonoraColors.green
                      : SonoraColors.muted,
                ),
              ),
              _DownloadButton(store: downloads, track: track),
              Text(
                formatDuration(track.duration ?? Duration.zero),
                style: const TextStyle(fontSize: 11, color: SonoraColors.muted),
              ),
              const SizedBox(width: 4),
            ],
          ),
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
    return error == null ? subtitle : Tooltip(message: error, child: subtitle);
  }
}

/// Downloads a track, retries a failed download, or removes a completed one.
///
/// The state comes straight from the store, so a download started on one screen
/// (or from a collection's "Download all") is reflected here and on every other
/// copy of the row.
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.store, required this.track});

  final DownloadStore store;
  final MediaItem track;

  @override
  Widget build(BuildContext context) {
    final progress = store.progressFor(track.id);
    if (progress != null) {
      final indeterminate = store.isProgressIndeterminate(track.id);
      final message = indeterminate
          ? 'Downloading'
          : 'Downloading ${(progress * 100).round()}%';
      return Tooltip(
        message: message,
        child: Semantics(
          label: message,
          liveRegion: true,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  value: indeterminate ? null : progress,
                  strokeWidth: 2,
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
        onPressed: () => store.remove(track.id),
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
  }
}

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider).value;
    final state = ref.watch(playbackProvider).value;
    if (track == null) return const SizedBox.shrink();
    final handler = ref.read(audioHandlerProvider);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: const Color(0xF0222623),
          child: InkWell(
            onTap: () => showNowPlaying(context),
            child: SizedBox(
              height: 66,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(7),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: Artwork(path: track.artPath),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
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
                        const SizedBox(height: 3),
                        Text(
                          track.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: SonoraColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next',
                    onPressed: handler.skipToNext,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                  IconButton(
                    tooltip: state?.playing == true ? 'Pause' : 'Play',
                    onPressed: state?.playing == true
                        ? handler.pause
                        : handler.play,
                    icon: Icon(
                      state?.playing == true
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showNowPlaying(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: SonoraColors.background,
    builder: (context) =>
        const FractionallySizedBox(heightFactor: 1, child: NowPlayingView()),
  );
}

class NowPlayingView extends ConsumerStatefulWidget {
  const NowPlayingView({super.key});

  @override
  ConsumerState<NowPlayingView> createState() => _NowPlayingViewState();
}

class _NowPlayingViewState extends ConsumerState<NowPlayingView> {
  /// Marks the seek bar so a slide on it seeks rather than changing volume.
  final _seekBarKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider).value;
    final state = ref.watch(playbackProvider).value;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    if (track == null) return const SizedBox.shrink();
    final duration = state?.processingState == AudioProcessingState.ready
        ? (track.duration ?? Duration.zero)
        : (track.duration ?? Duration.zero);
    final max = duration.inMilliseconds
        .toDouble()
        .clamp(1.0, double.infinity)
        .toDouble();
    final value = position.inMilliseconds.toDouble().clamp(0.0, max).toDouble();
    final handler = ref.read(audioHandlerProvider);
    final store = ref.watch(favoriteStoreProvider);
    final shuffleOn = state?.shuffleMode == AudioServiceShuffleMode.all;
    final repeatMode = state?.repeatMode ?? AudioServiceRepeatMode.none;
    final queued = ref.watch(queueProvider).value?.length ?? 0;
    final screen = MediaQuery.sizeOf(context);
    final artSize = math.min(screen.width - 48, screen.height * 0.46);
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              track.accent.withValues(alpha: 0.42),
              SonoraColors.background,
            ],
            stops: const [0, 0.62],
          ),
        ),
        child: _VolumeSwipe(
          seekBar: _seekBarKey,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 22),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Close player',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 30,
                            ),
                          ),
                          const Expanded(
                            child: Column(
                              children: [
                                Text(
                                  'NOW PLAYING',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: SonoraColors.muted,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'SONORA RADIO',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Up next',
                            onPressed: () => showQueue(context),
                            icon: const Icon(Icons.queue_music_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox.square(
                          dimension: artSize,
                          child: Artwork(path: track.artPath),
                        ),
                      ),
                      const SizedBox(height: 18),
                      ListenableBuilder(
                        listenable: store,
                        builder: (context, _) => Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    track.artist ?? '',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: SonoraColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Favorite',
                              onPressed: () => store.toggle(track),
                              icon: Icon(
                                store.contains(track.id)
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: store.contains(track.id)
                                    ? SonoraColors.green
                                    : SonoraColors.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      KeyedSubtree(
                        key: _seekBarKey,
                        child: Slider(
                          value: value,
                          max: max,
                          onChanged: (next) => handler.seek(
                            Duration(milliseconds: next.round()),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            formatDuration(position),
                            style: const TextStyle(
                              fontSize: 11,
                              color: SonoraColors.muted,
                            ),
                          ),
                          Text(
                            formatDuration(duration),
                            style: const TextStyle(
                              fontSize: 11,
                              color: SonoraColors.muted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            tooltip: shuffleOn ? 'Shuffle on' : 'Shuffle off',
                            onPressed: () => handler.setShuffleMode(
                              shuffleOn
                                  ? AudioServiceShuffleMode.none
                                  : AudioServiceShuffleMode.all,
                            ),
                            icon: Icon(
                              Icons.shuffle_rounded,
                              color: shuffleOn
                                  ? SonoraColors.green
                                  : SonoraColors.muted,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Previous',
                            onPressed: handler.skipToPrevious,
                            icon: const Icon(
                              Icons.skip_previous_rounded,
                              size: 38,
                            ),
                          ),
                          IconButton.filled(
                            style: IconButton.styleFrom(
                              backgroundColor: SonoraColors.text,
                              foregroundColor: Colors.black,
                              minimumSize: const Size(68, 68),
                            ),
                            tooltip: state?.playing == true ? 'Pause' : 'Play',
                            onPressed: state?.playing == true
                                ? handler.pause
                                : handler.play,
                            icon: Icon(
                              state?.playing == true
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 36,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Next',
                            onPressed: handler.skipToNext,
                            icon: const Icon(Icons.skip_next_rounded, size: 38),
                          ),
                          IconButton(
                            tooltip: switch (repeatMode) {
                              AudioServiceRepeatMode.one => 'Repeat one',
                              AudioServiceRepeatMode.all => 'Repeat all',
                              _ => 'Repeat off',
                            },
                            onPressed: () => handler.setRepeatMode(
                              nextRepeatMode(repeatMode),
                            ),
                            icon: Icon(
                              repeatMode == AudioServiceRepeatMode.one
                                  ? Icons.repeat_one_rounded
                                  : Icons.repeat_rounded,
                              color: repeatMode == AudioServiceRepeatMode.none
                                  ? SonoraColors.muted
                                  : SonoraColors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(
                            Icons.devices_rounded,
                            size: 19,
                            color: SonoraColors.green,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'This device',
                            style: TextStyle(
                              fontSize: 12,
                              color: SonoraColors.green,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => showQueue(context),
                            icon: const Icon(
                              Icons.queue_music_rounded,
                              size: 18,
                            ),
                            label: Text(
                              '$queued in queue',
                              style: const TextStyle(
                                fontSize: 12,
                                color: SonoraColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps the player so sliding left or right anywhere on it, the artwork
/// included, changes the volume, with the level shown while the finger is down.
///
/// This listens to raw pointer events rather than using a [GestureDetector].
/// Gesture detectors compete in the gesture arena, where the sheet's own drag
/// or the seek bar's horizontal drag can win and swallow the slide, which is
/// why a real finger changed nothing. A listener is not part of the arena, so
/// nothing can take the gesture away from it.
class _VolumeSwipe extends ConsumerStatefulWidget {
  const _VolumeSwipe({required this.child, this.seekBar});

  final Widget child;

  /// The seek bar keeps its own horizontal drag, so sliding on it seeks
  /// instead of changing the volume.
  final GlobalKey? seekBar;

  @override
  ConsumerState<_VolumeSwipe> createState() => _VolumeSwipeState();
}

class _VolumeSwipeState extends ConsumerState<_VolumeSwipe> {
  /// How far the finger must travel before a slide counts, so tapping the
  /// artwork does not nudge the volume.
  static const _slop = 10.0;

  int? _pointer;
  Offset? _down;
  double? _startVolume;
  bool _active = false;
  bool _visible = false;
  Timer? _hideTimer;

  /// Pixels of travel that cover the whole volume range.
  double _range = 300;

  bool _onSeekBar(Offset position) {
    final box = widget.seekBar?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    return rect.inflate(10).contains(position);
  }

  void _onDown(PointerDownEvent event) {
    if (_pointer != null || _onSeekBar(event.position)) return;
    _pointer = event.pointer;
    _down = event.position;
    _startVolume = ref.read(volumeProvider);
    _active = false;
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final down = _down;
    final start = _startVolume;
    if (down == null || start == null) return;
    final travel = event.position - down;
    if (!_active) {
      // Wait until the slide is clearly sideways, so a vertical drag is left
      // to whatever the user meant by it.
      if (travel.dx.abs() < _slop || travel.dx.abs() <= travel.dy.abs()) return;
      _hideTimer?.cancel();
      setState(() {
        _active = true;
        _visible = true;
      });
      // The device echoes the level back on every step it applies, which would
      // otherwise yank the readout back to a rounded value mid slide.
      ref.read(volumeProvider.notifier).beginSlide();
    }
    // Measured from where the finger went down, so the level can be fine
    // tuned from any starting point instead of jumping to the touch position.
    ref.read(volumeProvider.notifier).set(start + travel.dx / _range);
  }

  void _onUp(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _down = null;
    _startVolume = null;
    if (!_active) return;
    _active = false;
    // The device level is the truth once the slide is over, so it is read back
    // to settle the readout on the level that actually applied.
    ref.read(volumeProvider.notifier).endSlide();
    // Leave the level up long enough to read, then fade it away. The timer is
    // owned here so closing the player cancels it.
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // A slide across most of the width covers the whole range, so a short
        // drag does not slam the volume to silent or full.
        _range = math.max(120, constraints.maxWidth * 0.7);
        return Listener(
          // Opaque, so a slide also counts on bare background between the
          // artwork and the controls. Deferring to the child would let those
          // empty pixels swallow the pointer before it ever arrived here.
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onUp,
          child: Stack(
            children: [
              // The sheet's column is mostly empty space, and a column only
              // hit-tests where one of its children actually is, so a slide over
              // the gaps would otherwise never reach the listener below. This
              // fills those gaps for hit testing only; it is listed first so
              // the real controls are tested before it.
              const Positioned.fill(
                child: ColoredBox(color: Color(0x00000000)),
              ),
              widget.child,
              Positioned.fill(
                child: IgnorePointer(child: _VolumeOverlay(visible: _visible)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The level shown while sliding, and briefly after. Deliberately small and out
/// of the way: the speaker, the number, and a thin bar.
class _VolumeOverlay extends ConsumerWidget {
  const _VolumeOverlay({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(volumeProvider);
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 160),
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    switch (volume) {
                      0 => Icons.volume_off_rounded,
                      < 0.5 => Icons.volume_down_rounded,
                      _ => Icons.volume_up_rounded,
                    },
                    size: 20,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(volume * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: volume,
                  minHeight: 3,
                  backgroundColor: Colors.white24,
                  color: SonoraColors.green,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cycles the repeat button through off, repeat all and repeat one.
AudioServiceRepeatMode nextRepeatMode(AudioServiceRepeatMode mode) =>
    switch (mode) {
      AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
      AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
      _ => AudioServiceRepeatMode.none,
    };

/// Opens the list of tracks that next and previous walk through.
Future<void> showQueue(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: SonoraColors.background,
    builder: (context) =>
        const FractionallySizedBox(heightFactor: 0.72, child: _QueueView()),
  );
}

/// The current queue, with the track that is playing highlighted. Tapping a
/// row makes it the playing track without dropping the rest of the list.
class _QueueView extends ConsumerWidget {
  const _QueueView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider).value ?? const <MediaItem>[];
    final playingId = ref.watch(currentTrackProvider).value?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Center(
          child: Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: SonoraColors.muted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Up next', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                queue.isEmpty
                    ? 'Nothing queued yet.'
                    : '${_plural(queue.length, 'track')} in the queue',
                style: const TextStyle(color: SonoraColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: queue.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'Play something to build a queue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: SonoraColors.muted),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: queue.length,
                  itemBuilder: (context, index) {
                    final track = queue[index];
                    final playing = track.id == playingId;
                    return ListTile(
                      onTap: () => playAndRemember(ref, track, queue: queue),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Artwork(path: track.artPath),
                        ),
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: playing ? SonoraColors.green : null,
                        ),
                      ),
                      subtitle: Text(
                        track.artist ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: SonoraColors.muted,
                        ),
                      ),
                      trailing: playing
                          ? const Icon(
                              Icons.graphic_eq_rounded,
                              color: SonoraColors.green,
                            )
                          : Text(
                              formatDuration(track.duration ?? Duration.zero),
                              style: const TextStyle(
                                fontSize: 11,
                                color: SonoraColors.muted,
                              ),
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class Artwork extends StatelessWidget {
  const Artwork({required this.path, this.fit = BoxFit.cover, super.key});

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          'assets/art/neon-rain.png',
          fit: fit,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }
    return Image.asset(
      path,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      filterQuality: FilterQuality.medium,
    );
  }
}

extension MediaItemVisuals on MediaItem {
  String get artPath =>
      artUri?.toString() ??
      extras?['art'] as String? ??
      'assets/art/neon-rain.png';
  Color get accent => Color(extras?['accent'] as int? ?? 0xFF63E69D);
}

String formatDuration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
