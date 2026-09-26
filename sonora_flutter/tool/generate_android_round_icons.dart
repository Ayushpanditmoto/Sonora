// Generates the Android `ic_launcher_round` mipmaps for every density.
//
// `flutter_launcher_icons` (see pubspec.yaml) owns the square `ic_launcher`
// mipmaps and the adaptive-icon XML, but it does NOT emit `ic_launcher_round`,
// so those files were left behind from an older, superseded logo and drifted
// out of sync with the branding. This script re-renders them from the same
// source of truth used by the square icons so both variants match.
//
// Run from the sonora_flutter package root:
//   dart run tool/generate_android_round_icons.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Single source of truth, matching `flutter_launcher_icons.image_path`.
const sourcePath = 'assets/branding/sonora-app-icon-gradient-clean.png';

const resRoot = 'android/app/src/main/res';

/// Launcher icon edge length in px, keyed by density bucket.
const densities = <String, int>{
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

/// Writes `size`x`size` PNGs of [source], masked to a circle when [round].
///
/// The mask is antialiased over a one pixel band so the edge does not look
/// jagged at mdpi.
List<int> render(img.Image source, int size, {required bool round}) {
  final scaled = img.copyResize(
    source,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );
  if (!round) return img.encodePng(scaled);

  final out = img.Image(width: size, height: size, numChannels: 4);
  final c = (size - 1) / 2.0;
  final radius = size / 2.0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final s = scaled.getPixel(x, y);
      final dx = x - c, dy = y - c;
      final dist = math.sqrt(dx * dx + dy * dy);
      // Coverage falls from 1 at radius-0.5 to 0 at radius+0.5.
      final coverage = (radius + 0.5 - dist).clamp(0.0, 1.0);
      final a = (coverage * s.a).round();
      out.setPixelRgba(x, y, s.r.toInt(), s.g.toInt(), s.b.toInt(), a);
    }
  }
  return img.encodePng(out);
}

void main() {
  final file = File(sourcePath);
  if (!file.existsSync()) {
    stderr.writeln('Source icon not found: $sourcePath');
    exit(1);
  }
  final source = img.decodeImage(file.readAsBytesSync())!;
  stdout.writeln('Source: $sourcePath (${source.width}x${source.height})');

  for (final entry in densities.entries) {
    final dir = Directory('$resRoot/${entry.key}');
    if (!dir.existsSync()) {
      stderr.writeln('Missing density bucket: ${dir.path}');
      exit(1);
    }
    final out = File('${dir.path}/ic_launcher_round.png');
    final bytes = render(source, entry.value, round: true);
    out.writeAsBytesSync(bytes);
    stdout.writeln('  wrote ${out.path} (${entry.value}x${entry.value}, '
        '${bytes.length} bytes)');
  }
}


