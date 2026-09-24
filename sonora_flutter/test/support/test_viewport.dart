import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sets a phone-sized viewport and stops the shimmer from animating.
///
/// The shimmer is an endless travelling highlight, which by design never lets
/// `pumpAndSettle` run out of frames. Switching animations off is a real
/// accessibility setting the app already honours, so the skeletons stay on
/// screen as plain blocks and tests settle normally.
void useTestViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(() {
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    tester.view.reset();
  });
}
