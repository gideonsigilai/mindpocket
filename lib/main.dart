import 'package:material_ui/material_ui.dart';
import 'package:local_ai_studio/app/app.dart';
import 'package:local_ai_studio/app/app_controller.dart';
import 'package:local_ai_studio/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final controller = await AppController.bootstrap();
  runApp(LocalAiApp(controller: controller));
}
