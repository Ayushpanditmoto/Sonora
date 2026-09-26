import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/sonora_audio_handler.dart';
import 'now_playing.dart';

/// The mini player as the bottom bar of a pushed page, such as a playlist or
/// the downloads list.
///
/// A pushed page has no [NavigationBar] under the mini player, and the
/// [NavigationBar] on the tabs is what normally keeps clear of the system
/// navigation bar. Without it here, the row is drawn against the bottom edge of
/// the screen and underneath the gesture pill or the three button bar, because
/// the app runs edge to edge. The inset the body opts out of is added here
/// instead, so the player sits above the system bar rather than under it.
///
/// It renders nothing when there is no track, so a caller can set it as the
/// [Scaffold.bottomNavigationBar] unconditionally.
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTrack = ref.watch(currentTrackProvider).value != null;
    if (!hasTrack) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        8,
        4,
        8,
        4 + MediaQuery.paddingOf(context).bottom,
      ),
      child: const MiniPlayer(),
    );
  }
}
