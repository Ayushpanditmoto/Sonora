import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/music_api.dart';
import '../../services/youtube_api.dart';
import '../collection/collection_view.dart';
import '../shimmer.dart';
import '../components/common.dart';
import '../components/track_tile.dart';
import '../sonora_theme.dart';

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
          builder: (_) => CollectionView(collection: collection),
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
        const SectionHeader(title: 'Songs'),
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
        const SectionHeader(title: 'YouTube'),
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
        SectionHeader(title: title),
        const SizedBox(height: 10),
        CollectionGrid(
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
                      const NavBackButton(),
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
        SectionHeader(title: title),
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
