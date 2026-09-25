import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonora_flutter/ui/app_shell.dart';
import 'package:sonora_flutter/ui/shimmer.dart';

void main() {
  testWidgets('network artwork is decoded for its displayed pixel size', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 50,
            child: Artwork(path: 'https://cdn.test/cover.jpg'),
          ),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.memCacheWidth, 150);
    expect(image.filterQuality, FilterQuality.low);
    expect(image.fadeInDuration, Duration.zero);
  });

  testWidgets('local artwork uses a size-limited decode', (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 120,
            child: Artwork(path: 'assets/art/neon-rain.png'),
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final resizedProvider = image.image as ResizeImage;
    expect(resizedProvider.width, 240);
    expect(image.filterQuality, FilterQuality.low);
  });

  testWidgets('the loading shimmer avoids an offscreen shader layer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 100,
            child: SkeletonBox(width: 100, height: 100),
          ),
        ),
      ),
    );

    expect(find.byType(ShaderMask), findsNothing);
    expect(find.byType(DecoratedBox), findsWidgets);
  });
}
