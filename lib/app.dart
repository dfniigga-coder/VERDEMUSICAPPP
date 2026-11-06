import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/root_shell.dart';

class VerdeApp extends StatelessWidget {
  const VerdeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Verde',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const RootShell(),
    );
  }
}
