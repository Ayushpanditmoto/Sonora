import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The device's own media volume, as a level from silent (0) to loudest (1).
///
/// just_audio's `setVolume` is a per player gain multiplier and cannot follow
/// the hardware keys, so on Android this talks to the music stream directly.
/// Other platforms have no equivalent exposed to a Flutter app, so the caller
/// falls back to the player level there.
class SystemVolume {
  SystemVolume();

  static const _method = MethodChannel('com.panditfx.sonora/volume');
  static const _events = EventChannel('com.panditfx.sonora/volume_events');

  /// Whether the device volume can be read and written on this platform.
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether the channel really answers, probed once and then remembered.
  ///
  /// Being on Android is not enough: an older build has no such channel, and
  /// the platform then reports success for a call that did nothing. Reading
  /// once finds out for real, so the caller can fall back to the player level
  /// rather than leaving the volume stuck.
  Future<bool> get available async {
    if (!isSupported) return false;
    return await (_available ??= _probe());
  }

  Future<bool>? _available;

  Future<bool> _probe() async => await read() != null;

  /// The current level, or null when it cannot be read.
  Future<double?> read() async => (await readState())?.level;

  /// The number of steps the device volume moves in, or null when unknown.
  ///
  /// Android exposes a short ladder of levels rather than a smooth range, so
  /// this is what says which of those levels the screen may show.
  Future<int?> readSteps() async => (await readState())?.steps;

  /// The level and the size of the ladder it moves in, read in one go.
  ///
  /// Both come from the same reply so they cannot describe two different moments
  /// on a device whose volume keys may move it between two separate reads.
  Future<({double level, int steps})?> readState() async {
    if (!isSupported) return null;
    try {
      final reply = await _method.invokeMethod<dynamic>('getVolume');
      final level = _level(reply);
      if (level == null) return null;
      final steps = reply?['steps'];
      return (
        level: level,
        steps: steps is num && steps.toInt() > 1 ? steps.toInt() : 0,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Sets the device volume and reports the level that actually took effect.
  ///
  /// Returns null where there is no device volume to set, so the caller can
  /// fall back to the player level instead of leaving the volume stuck. The
  /// device moves in steps, so the level it settled on is what comes back, not
  /// the one that was asked for. That is what keeps the screen and the sound
  /// together: nothing has to be read back afterwards to find out.
  Future<double?> write(double level) async {
    if (!await available) return null;
    try {
      // Read as a plain value, not a map: the channel answers with the level
      // on its own, and asking for a map would throw on that.
      final reply = await _method.invokeMethod<dynamic>('setVolume', {
        'level': level.clamp(0.0, 1.0),
      });
      final applied = _level(reply);
      if (applied != null) return applied;
      // An older build acknowledges the call without saying where it landed.
      return level.clamp(0.0, 1.0).toDouble();
    } on MissingPluginException {
      // The channel went away after the probe.
      _available = Future<bool>.value(false);
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Pulls the level out of a platform reply, tolerating both the map with the
  /// step count and a bare number from an older build.
  static double? _level(dynamic reply) {
    final value = switch (reply) {
      final Map<dynamic, dynamic> map => map['level'],
      final num number => number,
      _ => null,
    };
    return value == null ? null : (value as num).toDouble().clamp(0.0, 1.0);
  }

  /// The level whenever it changes outside the app, for example on the
  /// hardware keys or from the system UI.
  Stream<double> get changes {
    if (!isSupported) return const Stream<double>.empty();
    return _events.receiveBroadcastStream().map(
      (event) => (event as num).toDouble().clamp(0.0, 1.0),
    );
  }
}

final systemVolumeProvider = Provider<SystemVolume>((ref) {
  return SystemVolume();
});
