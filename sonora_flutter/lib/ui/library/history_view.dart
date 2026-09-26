import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/play_and_remember.dart';
import '../../player/sonora_audio_handler.dart';
import '../../state/recent_store.dart';
import '../formatting.dart';
import '../player/now_playing.dart';
import '../components/common.dart';
import '../components/track_tile.dart';
import '../sonora_theme.dart';

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
                                  (track) => SwipeToRemove(
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

Future<void> confirmHistoryClear(
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
