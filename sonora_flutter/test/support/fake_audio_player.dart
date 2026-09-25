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
  final loadedHeaders = <Map<String, String>>[];
  final loadedPaths = <String>[];
  final failOnceUrls = <String>{};
  final seeks = <Duration?>[];
  final volumes = <double>[];
  final _loads = <({AudioSource source, Completer<Duration?> completer})>[];
  final _processingStates = StreamController<ProcessingState>.broadcast();
  int playCount = 0;
  int stopCount = 0;
  Completer<void>? playCompleter;

  @override
  LoopMode loopMode = LoopMode.off;
  AudioSource? _source;
  double _volume = 1;

  /// When set, [setUrl] fails with this just_audio error code instead of
  /// loading, standing in for a dead or expired stream url.
  int? failLoadsWith;

  /// Completes every pending load with a fake duration. The source becomes
  /// current only when its load succeeds, matching just_audio's behaviour while
  /// a different item is still buffering.
  void finishLoad() {
    for (final load in _loads) {
      if (!load.completer.isCompleted) {
        _source = load.source;
        load.completer.complete(const Duration(seconds: 3));
      }
    }
  }

  /// Emits a player state transition, such as a source reaching its end.
  void emitProcessingState(ProcessingState state) {
    _processingStates.add(state);
  }

  @override
  AudioSource? get audioSource => _source;

  @override
  Stream<PlaybackEvent> get playbackEventStream =>
      Stream<PlaybackEvent>.empty();

  @override
  Stream<ProcessingState> get processingStateStream => _processingStates.stream;

  bool _playing = false;

  @override
  bool get playing => _playing;

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
    loadedHeaders.add(
      Map<String, String>.unmodifiable(headers ?? const <String, String>{}),
    );
    final pending = _loads.isEmpty ? null : _loads.last;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.completeError(
        PlayerInterruptedException('Loading interrupted'),
      );
    }
    final source = AudioSource.uri(Uri.parse(url));
    if (failOnceUrls.remove(url)) {
      return Future<Duration?>.error(
        PlayerException(403, 'Response code: 403', null),
      );
    }
    final failure = failLoadsWith;
    if (failure != null) {
      return Future<Duration?>.error(
        PlayerException(failure, 'Source error', null),
      );
    }
    final load = (source: source, completer: Completer<Duration?>());
    _loads.add(load);
    return load.completer.future;
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
    _playing = true;
    await playCompleter?.future;
  }

  @override
  Future<void> pause() async {
    _playing = false;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    _playing = false;
    _source = null;
    for (final load in _loads) {
      if (!load.completer.isCompleted) {
        load.completer.completeError(
          PlayerInterruptedException('Loading interrupted'),
        );
      }
    }
    _processingStates.add(ProcessingState.idle);
  }

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
