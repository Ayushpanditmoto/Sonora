import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:sonora_flutter/player/system_volume.dart';

/// A stand-in for the device volume, so tests can see what the player writes
/// to the music stream and can push changes back as the hardware keys do.
class FakeSystemVolume extends SystemVolume {
  FakeSystemVolume({this.level = 1, this.writesWork = true, this.steps});

  double level;

  /// Set to false to stand in for a build with no volume channel, which forces
  /// the caller to fall back to the player level.
  bool writesWork;

  /// The size of the device volume ladder, as on a real device where the
  /// volume moves in a handful of steps. Null means a smooth range.
  final int? steps;

  final writes = <double>[];
  final _changes = StreamController<double>.broadcast();

  @override
  bool get isSupported => true;

  @override
  Future<bool> get available async => writesWork;

  @override
  Future<double?> read() async => level;

  @override
  Future<int?> readSteps() async => steps;

  @override
  Future<({double level, int steps})?> readState() async =>
      (level: level, steps: steps ?? 0);

  @override
  Future<double?> write(double level) async {
    if (!writesWork) return null;
    // The device can only land on its steps, so it rounds and reports back
    // what it really applied, exactly as the Android channel does.
    final applied = steps == null
        ? level
        : (level.clamp(0.0, 1.0) * steps!).round() / steps!;
    this.level = applied;
    writes.add(applied);
    _changes.add(applied);
    return applied;
  }

  @override
  Stream<double> get changes => _changes.stream;

  /// Simulates a hardware volume key or a change made in the system UI.
  void changeFromDevice(double level) {
    this.level = level;
    _changes.add(level);
  }

  Future<void> close() => _changes.close();
}

/// Stands in for [AudioPlayer] in tests: a load stays pending until
/// [finishLoad] is called, and starting a new load aborts the pending one
/// exactly the way just_audio does (which produces
/// `PlayerInterruptedException`).
class FakeAudioPlayer extends AudioPlayer {
  final loadedUrls = <String>[];
  final loadedPaths = <String>[];
  final seeks = <Duration?>[];
  final volumes = <double>[];
  final _loads = <Completer<Duration?>>[];
  int playCount = 0;

  @override
  LoopMode loopMode = LoopMode.off;
  AudioSource? _source;
  double _volume = 1;

  /// When set, [setUrl] fails with this just_audio error code instead of
  /// loading, standing in for a dead or expired stream url.
  int? failLoadsWith;

  /// Completes every pending load with a fake duration.
  void finishLoad() {
    for (final load in _loads) {
      if (!load.isCompleted) load.complete(const Duration(seconds: 3));
    }
  }

  @override
  AudioSource? get audioSource => _source;

  @override
  Stream<PlaybackEvent> get playbackEventStream =>
      Stream<PlaybackEvent>.empty();

  @override
  Stream<ProcessingState> get processingStateStream =>
      Stream<ProcessingState>.empty();

  @override
  bool get playing => false;

  @override
  ProcessingState get processingState => ProcessingState.ready;

  @override
  Duration get position => Duration.zero;

  @override
  Duration get bufferedPosition => Duration.zero;

  @override
  double get speed => 1;

  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) {
    loadedUrls.add(url);
    final pending = _loads.isEmpty ? null : _loads.last;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(PlayerInterruptedException('Loading interrupted'));
    }
    _source = AudioSource.uri(Uri.parse(url));
    final failure = failLoadsWith;
    if (failure != null) {
      return Future<Duration?>.error(
        PlayerException(failure, 'Source error', null),
      );
    }
    final load = Completer<Duration?>();
    _loads.add(load);
    return load.future;
  }

  @override
  Future<Duration?> setFilePath(
    String filePath, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) {
    // Tracked separately from setUrl so a test can tell playing the network
    // apart from playing a downloaded file.
    loadedPaths.add(filePath);
    _source = AudioSource.uri(Uri.file(filePath));
    return Future<Duration?>.value(const Duration(seconds: 3));
  }

  @override
  Future<void> play() async {
    playCount++;
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seeks.add(position);
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    loopMode = mode;
  }

  @override
  double get volume => _volume;

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    volumes.add(volume);
  }
}
