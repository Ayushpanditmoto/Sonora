import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonora_flutter/ui/sonora_theme.dart';

void main() {
  test('Sonora uses its dark music theme', () {
    final theme = SonoraTheme.dark;

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, SonoraColors.background);
    expect(theme.colorScheme.primary, SonoraColors.green);
  });
}
