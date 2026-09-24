import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonora_flutter/player/sonora_audio_handler.dart';
import 'package:sonora_flutter/player/system_volume.dart';
import 'package:sonora_flutter/services/music_api.dart';
import 'package:sonora_flutter/ui/app_shell.dart';
import 'package:sonora_flutter/ui/sonora_theme.dart';

import 'support/fake_audio_player.dart';
import 'support/test_viewport.dart';

/// A [SystemVolume] with no platform behind it, standing in for iOS or desktop
/// where no device volume is exposed to a Flutter app.
class UnavailableSystemVolume extends SystemVolume {
  UnavailableSystemVolume();

  @override
  bool get isSupported => false;

  @override
  Future<bool> get available async => false;

  @override
  Future<double?> read() async => null;

  @override
  Future<double?> write(double level) async => null;

  @override
  Stream<double> get changes => const Stream<double>.empty();
}

void main() {
  Future<(ProviderContainer, FakeSystemVolume, FakeAudioPlayer)> pumpApp(
    WidgetTester tester, {
    double deviceLevel = 1,
    bool useDevice = true,
    bool writesWork = true,
    SystemVolume? device,
  }) async {
    SharedPreferences.setMockInitialValues({});
    useTestViewport(tester);

    final fakeDevice = FakeSystemVolume(
      level: deviceLevel,
      writesWork: writesWork,
    );
    // The fake is only used when no specific device was handed in, so a test
    // that passes its own (for example one with a volume ladder) keeps it.
    final active = device ?? fakeDevice;
    // The fake that is actually wired up is the one returned, so a test that
    // passes its own (for example one with a volume ladder) asserts against the
    // same object the controller wrote to. A stand-in with no channel reports no
    // writes, which is what the fallback tests check.
    final activeFake = active is FakeSystemVolume ? active : fakeDevice;
    if (!identical(activeFake, fakeDevice)) addTearDown(activeFake.close);
    final player = FakeAudioPlayer();
    final handler = SonoraAudioHandler(player: player);
    final container = ProviderContainer(
      overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        positionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
        if (useDevice) systemVolumeProvider.overrideWithValue(active),
        catalogProvider.overrideWith(
          (ref) async => [
            MediaItem(
              id: '1',
              title: 'Song 1',
              artist: 'S',
              extras: {
                'url': 'https://cdn.test/1.mp3',
                'art': 'assets/art/neon-rain.png',
              },
            ),
          ],
        ),
        playlistsProvider.overrideWith((ref) async => const []),
        albumsProvider.overrideWith((ref) async => const []),
        artistsProvider.overrideWith((ref) async => const []),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(fakeDevice.close);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: SonoraTheme.dark, home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(HomeView),
        matching: find.byWidgetPredicate(
          (widget) => widget is TrackTile && widget.track.id == '1',
        ),
      ),
    );
    player.finishLoad();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    // The fake that is actually wired up is the one returned, so a test that
    // passes its own (for example one with a volume ladder) asserts against the
    // same object the controller wrote to.
    return (container, activeFake, player);
  }

  testWidgets(
    'sliding writes to the device music stream, not just the player',
    (tester) async {
      final (container, device, player) = await pumpApp(tester);

      container.read(volumeProvider.notifier).set(0.5);
      await tester.pumpAndSettle();

      expect(
        device.writes.last,
        closeTo(0.5, 0.001),
        reason: 'the slide must reach the device volume',
      );
      expect(
        player.volumes,
        isEmpty,
        reason:
            'just_audio gain is left alone: it cannot track the hardware keys',
      );
    },
  );

  testWidgets('the player shows the device level when it opens', (
    tester,
  ) async {
    final (container, _, _) = await pumpApp(tester, deviceLevel: 0.3);

    expect(
      container.read(volumeProvider),
      closeTo(0.3, 0.001),
      reason: 'a phone already at 30% must not be shown as 100%',
    );
  });

  testWidgets('a hardware volume key moves the level shown in the player', (
    tester,
  ) async {
    final (container, device, _) = await pumpApp(tester);

    device.changeFromDevice(0.4);
    await tester.pumpAndSettle();

    expect(container.read(volumeProvider), closeTo(0.4, 0.001));
    expect(find.text('40%'), findsOneWidget);
  });

  testWidgets('unmuting returns to the previous level, not full volume', (
    tester,
  ) async {
    final (container, device, _) = await pumpApp(tester);
    final controller = container.read(volumeProvider.notifier);

    controller.set(0.6);
    await tester.pumpAndSettle();
    controller.toggleMute();
    await tester.pumpAndSettle();
    expect(container.read(volumeProvider), 0);
    expect(device.writes.last, 0);

    controller.toggleMute();
    await tester.pumpAndSettle();
    expect(container.read(volumeProvider), closeTo(0.6, 0.001));
  });

  testWidgets('without a device volume the player level is used', (
    tester,
  ) async {
    // An older build: the platform is Android but the volume channel is not
    // there, so writes come back false and the player gain takes over.
    final (container, device, player) = await pumpApp(
      tester,
      writesWork: false,
    );

    container.read(volumeProvider.notifier).set(0.35);
    await tester.pumpAndSettle();

    expect(
      player.volumes.last,
      closeTo(0.35, 0.001),
      reason: 'the swipe must still change something on other platforms',
    );
    expect(device.writes, isEmpty);
  });

  testWidgets('a platform with no device volume uses the player level', (
    tester,
  ) async {
    // iOS and desktop expose no device volume to a Flutter app, so the player
    // gain has to carry the swipe there.
    final (container, device, player) = await pumpApp(
      tester,
      device: UnavailableSystemVolume(),
    );

    container.read(volumeProvider.notifier).set(0.45);
    await tester.pumpAndSettle();

    expect(player.volumes.last, closeTo(0.45, 0.001));
    expect(device.writes, isEmpty);
  });

  testWidgets('the level is held between 0 and 1', (tester) async {
    final (container, device, _) = await pumpApp(tester);
    final controller = container.read(volumeProvider.notifier);

    controller.set(5);
    await tester.pumpAndSettle();
    expect(container.read(volumeProvider), 1);

    controller.set(-3);
    await tester.pumpAndSettle();
    expect(container.read(volumeProvider), 0);
    expect(device.writes.last, 0);
  });

  testWidgets('the readout never shows a level the device cannot be on', (
    tester,
  ) async {
    // A real device moves the music volume in a short ladder, so asking for a
    // level between two steps would otherwise show one number and apply
    // another, which is the desync this guards.
    final (container, device, _) = await pumpApp(
      tester,
      device: FakeSystemVolume(level: 1, steps: 15),
    );
    final controller = container.read(volumeProvider.notifier);

    controller.set(0.22);
    await tester.pumpAndSettle();
    // 0.22 sits between step 3 (0.2) and step 4 (0.2667).
    expect(container.read(volumeProvider), closeTo(0.2, 0.001));
    expect(
      device.level,
      closeTo(container.read(volumeProvider), 0.001),
      reason:
          'writes=${device.writes} steps=${device.steps} level=${device.level}',
    );

    controller.set(0.9);
    await tester.pumpAndSettle();
    expect(container.read(volumeProvider), closeTo(device.level, 0.001));
  });

  testWidgets('a slide is not dragged backwards by the device echo', (
    tester,
  ) async {
    final (container, device, _) = await pumpApp(
      tester,
      device: FakeSystemVolume(level: 1, steps: 15),
    );
    final controller = container.read(volumeProvider.notifier);
    await tester.pumpAndSettle();

    controller.beginSlide();
    controller.set(0.5);
    // The device answers every write. Those echoes are ignored while sliding,
    // so the number under the finger stays where the finger put it, snapped to
    // the nearest step (0.5 is between steps 7 and 8, so it lands on 8/15).
    expect(container.read(volumeProvider), closeTo(0.5333, 0.001));
    device.changeFromDevice(0.4667);
    await tester.pumpAndSettle();
    expect(container.read(volumeProvider), closeTo(0.5333, 0.001));

    controller.endSlide();
    // Once the slide is over, the device level is the truth again.
    device.changeFromDevice(0.4667);
    await tester.pumpAndSettle();
    expect(container.read(volumeProvider), closeTo(0.4667, 0.001));
  });

  testWidgets('a level chosen before the device is read is not thrown away', (
    tester,
  ) async {
    // Sliding as soon as the player opens beats waiting for the device, and the
    // level read a moment later must not undo the gesture.
    final (container, device, _) = await pumpApp(
      tester,
      device: FakeSystemVolume(level: 1, steps: 15),
    );
    final controller = container.read(volumeProvider.notifier);

    controller.set(0.22);
    await tester.pumpAndSettle();
    expect(container.read(volumeProvider), closeTo(0.2, 0.001));
    expect(device.level, closeTo(0.2, 0.001));
  });

  testWidgets('the level settles on the device level once a slide ends', (
    tester,
  ) async {
    // The device volume is the truth, so when the finger comes up the readout
    // has to end on the level the device actually applied. Skipping that read
    // is what leaves the player showing one level while the phone is on
    // another.
    final (container, device, _) = await pumpApp(
      tester,
      device: FakeSystemVolume(level: 1, steps: 15),
    );
    final controller = container.read(volumeProvider.notifier);
    await tester.pumpAndSettle();

    controller.beginSlide();
    controller.set(0.5);
    // The write echoes the step the device rounded to, which is ignored while
    // the finger is still down.
    await tester.pumpAndSettle();
    expect(container.read(volumeProvider), closeTo(0.5333, 0.001));

    // Something outside the app moves the level right before the finger lifts:
    // a hardware key, or another app taking the stream.
    device.changeFromDevice(0.2);
    await tester.pumpAndSettle();
    expect(
      container.read(volumeProvider),
      closeTo(0.5333, 0.001),
      reason: 'the echo must not move the readout mid slide',
    );

    controller.endSlide();
    await tester.pumpAndSettle();
    expect(
      container.read(volumeProvider),
      closeTo(device.level, 0.001),
      reason: 'the readout must settle on the level the device is really on',
    );
    expect(container.read(volumeProvider), closeTo(0.2, 0.001));
  });

  testWidgets('a smooth device range is left exactly as asked', (tester) async {
    final (container, _, _) = await pumpApp(tester);
    container.read(volumeProvider.notifier).set(0.37);
    await tester.pumpAndSettle();
    expect(container.read(volumeProvider), closeTo(0.37, 0.001));
  });
}
