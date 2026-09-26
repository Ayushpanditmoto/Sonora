import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../sonora_theme.dart';

class Artwork extends StatelessWidget {
  const Artwork({required this.path, this.fit = BoxFit.cover, super.key});

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // API artwork is 500 px square, but a track row displays it at about
        // 50 logical pixels. Decoding the full source for every row wastes
        // memory and makes image completion contend with scrolling frames.
        // Derive the decode size from the laid-out artwork and device pixel
        // ratio so sharp displays still receive enough pixels.
        int? decodeWidth;
        if (constraints.maxWidth.isFinite && constraints.maxHeight.isFinite) {
          final logicalSize = math.min(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          if (logicalSize > 0) {
            decodeWidth = math.max(
              1,
              (logicalSize * MediaQuery.devicePixelRatioOf(context)).ceil(),
            );
          }
        }

        Widget fallback() => Image.asset(
          'assets/art/neon-rain.png',
          fit: fit,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: decodeWidth,
          filterQuality: FilterQuality.low,
        );

        if (path.startsWith('http://') || path.startsWith('https://')) {
          return CachedNetworkImage(
            imageUrl: path,
            fit: fit,
            width: double.infinity,
            height: double.infinity,
            memCacheWidth: decodeWidth,
            filterQuality: FilterQuality.low,
            placeholder: (context, url) =>
                const ColoredBox(color: SonoraColors.surfaceHigh),
            errorWidget: (context, url, error) => fallback(),
            // Loading is background work, not an interaction. Avoiding a
            // cross-fade also prevents a short opacity layer on every image.
            placeholderFadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            fadeInDuration: Duration.zero,
          );
        }
        return Image.asset(
          path,
          fit: fit,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: decodeWidth,
          filterQuality: FilterQuality.low,
          errorBuilder: (context, error, stackTrace) => fallback(),
        );
      },
    );
  }
}

extension MediaItemVisuals on MediaItem {
  String get artPath =>
      artUri?.toString() ??
      extras?['art'] as String? ??
      'assets/art/neon-rain.png';
  Color get accent => Color(extras?['accent'] as int? ?? 0xFF63E69D);
}

String formatDuration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
