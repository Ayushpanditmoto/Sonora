import 'package:flutter/material.dart';

import 'sonora_theme.dart';

/// A soft highlight that travels across its child, used everywhere something is
/// still loading.
///
/// The highlight is painted as a foreground gradient rather than a shader mask.
/// A [ShaderMask] creates an offscreen compositing layer for every skeleton;
/// keeping this as a direct decoration avoids that GPU work on 120 Hz displays.
class Shimmer extends StatefulWidget {
  const Shimmer({required this.child, super.key});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A steady block still says "loading"; a travelling one does not suit
    // someone who has asked the system for less motion.
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final travel = 2 * (1 - _controller.value);
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1 - travel, 0),
              end: Alignment(1 - travel, 0),
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.1),
                Colors.transparent,
              ],
              stops: const [0.3, 0.5, 0.7],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A shimmering placeholder the size and shape of the content it stands in for.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    required this.width,
    required this.height,
    this.radius = 6,
    super.key,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: SonoraColors.surfaceHigh,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// Placeholders shaped like the track rows a list is about to fill with.
class SkeletonTrackList extends StatelessWidget {
  const SkeletonTrackList({this.count = 6, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          SizedBox(
            height: 68,
            child: Row(
              children: [
                const SkeletonBox(width: 50, height: 50, radius: 5),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonBox(width: 170, height: 13),
                      SizedBox(height: 7),
                      SkeletonBox(width: 110, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A shimmering stand-in for artwork while it downloads, shown behind the real
/// image so the tile never jumps from empty to full size.
class ArtworkPlaceholder extends StatelessWidget {
  const ArtworkPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: ColoredBox(
        color: SonoraColors.surfaceHigh,
        child: SizedBox.expand(),
      ),
    );
  }
}
