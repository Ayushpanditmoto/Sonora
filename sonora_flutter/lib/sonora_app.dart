import 'package:flutter/material.dart';

import 'ui/app_shell.dart';
import 'ui/sonora_theme.dart';

class SonoraApp extends StatelessWidget {
  const SonoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sonora',
      debugShowCheckedModeBanner: false,
      theme: SonoraTheme.dark,
      home: const AppShell(),
    );
  }
}
