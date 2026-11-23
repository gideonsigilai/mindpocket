import 'package:material_ui/material_ui.dart';

import 'app_controller.dart';
import 'app_theme.dart';
import 'presentation/main_shell.dart';

class LocalAiApp extends StatelessWidget {
  const LocalAiApp({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Loom Local AI',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark,
    home: MainShell(controller: controller),
  );
}
