import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/sonora_audio_handler.dart';
import '../../state/download_store_provider.dart';
import '../../state/favorite_store.dart';
import '../../state/play_and_remember.dart';
import '../components/artwork.dart';
import '../components/track_tile.dart';
import '../formatting.dart';
import '../sonora_theme.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider).value;
    final state = ref.watch(playbackProvider).value;
    final isLoading =
        state?.processingState == AudioProcessingState.loading ||
        state?.processingState == AudioProcessingState.buffering;
    if (track == null) return const SizedBox.shrink();
    final handler = ref.read(audioHandlerProvider);
    // Playback state changes several times per second. Keeping this row in its
    // own repaint boundary prevents those small updates from repainting the
    // navigation bar around it.
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
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
                    tooltip: isLoading
                        ? 'Preparing track'
                        : state?.playing == true
                        ? 'Pause'
                        : 'Play',
                    onPressed: isLoading
                        ? null
                        : state?.playing == true
                        ? handler.pause
                        : handler.play,
                    icon: isLoading
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
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
    final isLoading =
        state?.processingState == AudioProcessingState.loading ||
        state?.processingState == AudioProcessingState.buffering;
    final isResolving = state?.processingState == AudioProcessingState.loading;
    final duration = track.duration ?? Duration.zero;
    final max = duration.inMilliseconds
        .toDouble()
        .clamp(1.0, double.infinity)
        .toDouble();
    final value = position.inMilliseconds.toDouble().clamp(0.0, max).toDouble();
    final handler = ref.read(audioHandlerProvider);
    final store = ref.watch(favoriteStoreProvider);
    final downloads = ref.watch(downloadStoreProvider);
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
                                  if (playCountText(track)
                                      case final playCount?) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.headphones_rounded,
                                          size: 14,
                                          color: SonoraColors.muted,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          playCount,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: SonoraColors.muted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
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
                            DownloadButton(store: downloads, track: track),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      KeyedSubtree(
                        key: _seekBarKey,
                        child: Slider(
                          value: value,
                          max: max,
                          onChanged: isResolving
                              ? null
                              : (next) => handler.seek(
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
                            tooltip: isLoading
                                ? 'Preparing track'
                                : state?.playing == true
                                ? 'Pause'
                                : 'Play',
                            onPressed: isLoading
                                ? null
                                : state?.playing == true
                                ? handler.pause
                                : handler.play,
                            icon: isLoading
                                ? const SizedBox.square(
                                    dimension: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.black,
                                    ),
                                  )
                                : Icon(
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
                    : '${plural(queue.length, 'track')} in the queue',
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
