import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_item_codec.dart';
import 'system_volume.dart';

final audioHandlerProvider = Provider<SonoraAudioHandler>(
  (ref) => throw UnimplementedError('Audio handler has not been initialized.'),
);
final playbackProvider = StreamProvider<PlaybackState>(
  (ref) => ref.watch(audioHandlerProvider).playbackState,
);
final currentTrackProvider = StreamProvider<MediaItem?>(
  (ref) => ref.watch(audioHandlerProvider).mediaItem,
);
final queueProvider = StreamProvider<List<MediaItem>>(
  (ref) => ref.watch(audioHandlerProvider).queue,
);
final positionProvider = StreamProvider<Duration>(
  (ref) => AudioService.position,
);

/// A playback failure worth telling the user about, such as a stream url that
/// has expired or a network that has dropped.
final playbackErrorProvider = StreamProvider<String>(
  (ref) => ref.watch(audioHandlerProvider).errors,
);

/// The output volume, from silent (0) to loudest (1).
///
/// On Android this is the device's music stream, so the hardware keys, the
/// system UI and the player screen all show and change the same level. Where
/// the device volume cannot be reached, it falls back to the player's own
/// level so the swipe still does something.
class VolumeController extends Notifier<double> {
  /// The level unmuting goes back to, so a muted player does not always come
  /// back at full blast.
  double _lastAudible = 1;

  /// How many volume steps the device volume actually has, or null when the
  /// device volume is not in use.
  int? _deviceSteps;

  /// True while the user is sliding, so a level reported back by the device
  /// cannot fight the gesture that is still going on.
  bool _sliding = false;

  /// True once a level has been chosen in this session, so the level read when
  /// connecting cannot overwrite a choice the user already made.
  bool _userSet = false;

  /// False once the notifier is torn down, so a late device callback cannot
  /// write to a disposed state.
  bool _alive = true;

  StreamSubscription<double>? _device;

  @override
  double build() {
    ref.onDispose(() {
      _alive = false;
      unawaited(_device?.cancel());
    });
    // The device volume is only used once the channel proves it answers, so a
    // build without it falls back to the player instead of showing a level
    // that nothing will actually honour.
    unawaited(_connect());
    return 1;
  }

  Future<void> _connect() async {
    final device = ref.watch(systemVolumeProvider);
    final avail = await device.available;
    if (!avail || !_alive) return;
    // Start from the real level rather than assuming full volume. The level and
    // the size of the ladder it moves in are read together, so the readout is
    // put on a level the device can really be on.
    final current = await device.readState();
    if (current == null || !_alive) return;
    // The channel answered a read and a write, so the device is what decides
    // the level from here, including settling the readout once a slide ends.
    _deviceInUse = true;
    if (current.steps > 1) _deviceSteps = current.steps;
    if (current.level > 0) _lastAudible = current.level;
    // Reading the device takes a moment, and the player can be opened and
    // slid in that time. Adopting the level read now would throw that gesture
    // away, so a level already chosen by the user is kept and merely snapped
    // onto the ladder instead.
    state = _userSet ? _snap(state) : _snap(current.level);
    _device ??= device.changes.listen(_onDeviceChanged);
  }

  /// Follows a change made outside the app, such as a hardware volume key.
  void _onDeviceChanged(double level) {
    // A level reported while the user is sliding is the device echoing back the
    // step it rounded to, not a change they asked for. Letting it through would
    // snap the readout backwards mid gesture, so it is left until the slide
    // ends. A hardware key press during a slide still lands then.
    if (_sliding) return;
    // A change made outside the app is authoritative, so it is always shown.
    if (level > 0) _lastAudible = level;
    state = _snap(level);
  }

  /// True once the device volume has proved it can be read and written, so the
  /// device is the one that decides the level.
  ///
  /// Without this, a platform that has no device volume to read would hand back
  /// a stale value and undo the slide the instant the finger came up.
  bool _deviceInUse = false;

  /// Marks the start of a slide, ignoring device echoes until [endSlide].
  void beginSlide() => _sliding = true;

  /// Ends a slide and takes the device's level, which is the truth once the
  /// gesture is over.
  void endSlide() {
    if (!_sliding) return;
    _sliding = false;
    // The device only has a say when it is the thing being set. Otherwise the
    // level the slide ended on is the right one, and reading would replace it
    // with a value from a volume the app is not even using.
    if (!_deviceInUse) return;
    final device = ref.read(systemVolumeProvider);
    if (!_alive) return;
    unawaited(
      device.read().then((level) {
        if (level == null || !_alive || _sliding || _writeId != _writeId) {
          return;
        }
        if (level > 0) _lastAudible = level;
        state = _snap(level);
      }),
    );
  }

  /// The device volume is a short ladder rather than a smooth 0..1 range, so a
  /// level that is not one of its steps rounds to the step that is.
  ///
  /// Showing the requested level instead would make the readout disagree with
  /// what the device actually applies, which is exactly the desync this avoids:
  /// the user would set 22% and hear 20%, with no way to tell from the screen.
  double _snap(double level) {
    final steps = _deviceSteps;
    if (steps == null || steps <= 1) return level;
    return (level * steps).round() / steps;
  }

  /// Sets the volume, ignoring values that would not change anything.
  void set(double value) {
    _userSet = true;
    // Snapped before it is shown and written, so the readout is always a level
    // the device can actually be on rather than one it would round away.
    final next = _snap(value.clamp(0.0, 1.0).toDouble());
    if (next == state) return;
    if (next > 0) _lastAudible = next;
    state = next;
    unawaited(_apply(next));
  }

  /// Bumped for every write so a slow answer that arrives late cannot pull the
  /// display back to a level the user has already slid past.
  int _writeId = 0;

  /// Puts [level] on the device volume, falling back to the player's own level
  /// when the device cannot be reached.
  ///
  /// The device answers with the level it actually applied, which is shown
  /// straight away. Reading the volume back instead would race the next slide:
  /// on a device with a short volume ladder, setting 22% gives 20%, and a read
  /// that lands mid gesture snaps the readout backwards to 20% while the finger
  /// is still moving.
  Future<void> _apply(double level) async {
    final device = ref.read(systemVolumeProvider);
    final writeId = ++_writeId;
    final applied = await device.write(level);
    if (!_alive || writeId != _writeId) return;
    if (applied == null) {
      // No device volume here (iOS, desktop, or an older build), so the player
      // gain is used and the swipe still does something.
      unawaited(ref.read(audioHandlerProvider).setVolume(level));
      return;
    }
    if (applied > 0) _lastAudible = applied;
    // While the finger is still down the level keeps moving, so a correction
    // from an earlier step would pull the readout backwards under the hand.
    // The level the slide ended on is read instead, once it is over.
    if (_sliding) return;
    if (applied != state) state = applied;
  }

  void toggleMute() => set(state == 0 ? _lastAudible : 0);
}

final volumeProvider = NotifierProvider<VolumeController, double>(
  VolumeController.new,
);

class SonoraAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  /// [player] and [localPathFor] are only injected by tests; the app always uses
  /// a real player and the real download store.
  SonoraAudioHandler({
    AudioPlayer? player,
    String? Function(String id)? localPathFor,
  }) : _player = player ?? AudioPlayer(),
       _localPathFor = localPathFor ?? ((_) => null) {
    // Tells Android this is local playback, which routes the media session to
    // the music stream so the hardware volume keys adjust the same level the
    // player screen shows.
    androidPlaybackInfo.add(LocalAndroidPlaybackInfo());
    _player.playbackEventStream.listen((_) => _broadcast());
    _player.processingStateStream.listen((state) {
      if (state != ProcessingState.completed) return;
      if (_repeatMode == AudioServiceRepeatMode.one) {
        unawaited(_restartCurrent());
        return;
      }
      unawaited(skipToNext());
    });
  }

  final AudioPlayer _player;

  /// The on-device copy of a track, or null when it has not been downloaded.
  ///
  /// A downloaded track is played from its own file, so it needs no connection
  /// and does not depend on a stream url that may since have expired.
  final String? Function(String id) _localPathFor;

  /// The underlying player, so tests can inspect loads, seeks and volume.
  AudioPlayer get player => _player;

  final _random = Random();
  int _index = 0;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  AudioServiceShuffleMode _shuffleMode = AudioServiceShuffleMode.none;

  static const _sessionKey = 'sonora.last_session';

  final _errors = StreamController<String>.broadcast();

  /// Playback failures, phrased for the user. Exposed instead of thrown because
  /// the UI starts playback without awaiting it, so an error raised there would
  /// otherwise surface as an uncaught exception rather than a message.
  Stream<String> get errors => _errors.stream;

  /// Bumped for every load request so a superseded load can be recognised.
  int _loadId = 0;

  /// Puts the last played track and its queue back after a restart.
  ///
  /// Only the state is restored: the track is shown in the mini player and in
  /// the player, paused and ready, without a network load or sound on its own.
  Future<void> restoreLastSession() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_sessionKey);
    if (stored == null) return;
    final session = decodeLastSession(stored);
    if (session == null) return;
    queue.add(List.unmodifiable(session.tracks));
    final at = session.currentId == null
        ? -1
        : session.tracks.indexWhere((track) => track.id == session.currentId);
    _index = at < 0 ? 0 : at;
    mediaItem.add(session.tracks[_index]);
    _broadcast();
  }

  /// Remembers the playing track so the next launch can restore it.
  void _saveSession() {
    final current = mediaItem.value;
    if (current == null || queue.value.isEmpty) return;
    unawaited(_writeSession(current));
  }

  /// Written without being awaited, so a storage failure is swallowed rather
  /// than escaping as an uncaught error: losing the last song across a restart
  /// is a smaller problem than interrupting playback over it.
  Future<void> _writeSession(MediaItem current) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _sessionKey,
        encodeLastSession(current: current, queue: queue.value),
      );
    } catch (_) {
      // Storage is unavailable; playback carries on.
    }
  }

  /// Replaces the queue that next and previous walk through.
  ///
  /// The playing track keeps its place when the new list still contains it, so
  /// replacing the queue (say, by opening another album) does not lose the
  /// current position. Otherwise playback points at the first track of the new
  /// list, which is also what stops [_index] going stale for a shorter queue.
  Future<void> loadQueue(List<MediaItem> tracks) async {
    queue.add(List.unmodifiable(tracks));
    final current = mediaItem.value;
    final keep = current == null
        ? -1
        : tracks.indexWhere((track) => track.id == current.id);
    if (keep < 0) {
      _index = 0;
      if (tracks.isNotEmpty) mediaItem.add(tracks.first);
    } else {
      _index = keep;
    }
    _broadcast();
    _saveSession();
  }

  /// Loads [item] and starts playing it.
  ///
  /// Starting a load aborts whatever load is still in flight, and just_audio
  /// reports that abort as [PlayerInterruptedException] ("Loading interrupted")
  /// on the previous call. Taps, the notification and the completion handler
  /// can all request a new track while an earlier one is still buffering, so
  /// that interruption is expected here and is swallowed by
  /// [_ignoreInterruptions] instead of escaping through the futures the UI
  /// fires without awaiting.
  Future<void> playTrack(MediaItem item) async {
    // A downloaded track plays from its own file. A stream url is then neither
    // needed nor consulted, so a download made months ago still plays and a
    // track with an expired link still works offline.
    final localPath = _localPathFor(item.id);
    final url = item.extras?['url'] as String?;
    if (localPath == null && (url == null || url.isEmpty)) return;

    // The source is already loaded, so restarting it needs no network load and
    // cannot interrupt anything else.
    final alreadyLoaded =
        mediaItem.value?.id == item.id && _player.audioSource != null;

    _index = queue.value.indexWhere((track) => track.id == item.id);
    if (_index < 0) {
      queue.add([item, ...queue.value.where((track) => track.id != item.id)]);
      _index = 0;
    }
    mediaItem.add(item);
    // Publish the new track straight away: the media session and the queue view
    // both read queueIndex from the playback state, and waiting for the next
    // player event would leave it pointing at the previous track.
    _broadcast();
    _saveSession();

    final loadId = ++_loadId;
    await _ignoreInterruptions(() async {
      if (alreadyLoaded) {
        await _player.seek(Duration.zero);
      } else if (localPath != null) {
        await _player.setFilePath(localPath);
      } else {
        await _player.setUrl(url!);
      }
      if (loadId != _loadId) return; // Superseded while loading.
      await _player.play();
    });
  }

  @override
  Future<void> play() async {
    if (_player.audioSource == null && mediaItem.value != null) {
      await playTrack(mediaItem.value!);
      return;
    }
    await _ignoreInterruptions(_player.play);
  }

  @override
  Future<void> pause() => _ignoreInterruptions(_player.pause);

  @override
  Future<void> stop() async {
    _loadId++; // Abandon any load that is still in flight.
    await _ignoreInterruptions(_player.stop);
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) =>
      _ignoreInterruptions(() => _player.seek(position));

  /// Sets the output volume, from silent (0) to loudest (1).
  Future<void> setVolume(double value) =>
      _player.setVolume(value.clamp(0.0, 1.0).toDouble());

  @override
  Future<void> skipToNext() async {
    if (_index >= queue.value.length - 1) {
      if (_repeatMode != AudioServiceRepeatMode.all || queue.value.isEmpty) {
        return;
      }
      await playTrack(queue.value.first);
      return;
    }
    await playTrack(queue.value[++_index]);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position > const Duration(seconds: 4)) {
      await seek(Duration.zero);
      return;
    }
    if (_index <= 0) {
      // Only repeat all goes back past the first track.
      if (_repeatMode != AudioServiceRepeatMode.all || queue.value.isEmpty) {
        return;
      }
      await playTrack(queue.value.last);
      return;
    }
    await playTrack(queue.value[--_index]);
  }

  /// Repeats the loaded track. Loop mode on the player normally handles
  /// [AudioServiceRepeatMode.one] without ever reaching `completed`; this is the
  /// fallback for the platforms that still report it.
  Future<void> _restartCurrent() async {
    final item = mediaItem.value;
    if (item == null) return;
    await playTrack(item);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeatMode = repeatMode;
    // Looping the loaded (single) source keeps "repeat one" gapless.
    await _ignoreInterruptions(
      () => _player.setLoopMode(
        repeatMode == AudioServiceRepeatMode.one ? LoopMode.one : LoopMode.off,
      ),
    );
    _broadcast();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _shuffleMode = shuffleMode;
    if (shuffleMode == AudioServiceShuffleMode.all) _shuffleRestOfQueue();
    _broadcast();
  }

  /// Randomises the tracks that are still to come, keeping the track that is
  /// playing in place. Disabling shuffle later keeps this order; loading a queue
  /// again (for example by reopening an album) restores the original one.
  void _shuffleRestOfQueue() {
    final current = mediaItem.value;
    final upcoming = [...queue.value]..shuffle(_random);
    if (current != null) {
      upcoming
        ..removeWhere((item) => item.id == current.id)
        ..insert(0, current);
    }
    queue.add(List.unmodifiable(upcoming));
    _index = 0;
  }

  /// Runs [action] while ignoring [PlayerInterruptedException].
  ///
  /// just_audio raises it whenever a load, play or seek is superseded by a newer
  /// request. That is a normal race between user actions rather than a playback
  /// failure, so it must not escape into the un-awaited futures created by the
  /// UI and the media session.
  Future<void> _ignoreInterruptions(Future<void> Function() action) async {
    try {
      await action();
    } on PlayerInterruptedException {
      // A newer request owns playback from here.
    } catch (error) {
      // Anything else is a real failure. It is reported rather than rethrown
      // because the UI and the media session both start playback without
      // awaiting it, where an error would surface as an uncaught exception
      // instead of something the user can read and retry.
      if (_errors.isClosed) return;
      _errors.add(
        error is PlayerException
            ? 'This track could not be played. Its audio may no longer be available.'
            : 'Something went wrong while playing this track.',
      );
    }
  }

  void _broadcast() {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          _player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _index,
        repeatMode: _repeatMode,
        shuffleMode: _shuffleMode,
      ),
    );
  }
}
