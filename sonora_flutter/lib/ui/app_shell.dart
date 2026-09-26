import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/sonora_audio_handler.dart';
import 'drawer/app_drawer.dart';
import 'home/home_view.dart';
import 'library/library_view.dart';
import 'player/now_playing.dart';
import 'search/search_view.dart';
import 'sonora_theme.dart';

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

/// Deletes a download only after [context] has confirmed the action.
///
/// This is used by the row's explicit Remove control. A swipe is intentionally
/// not a delete gesture: the row remains until the user confirms here.
