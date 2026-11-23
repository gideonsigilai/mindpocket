import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_studio/app/models/installed_model.dart';
import 'package:local_ai_studio/app/presentation/widgets/local_model_picker.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('selecting an installed model reports that model', (
    tester,
  ) async {
    final models = [
      const InstalledModel(
        name: 'first.gguf',
        repository: 'team/first',
        filename: 'first.gguf',
        path: r'C:\models\first.gguf',
        sizeBytes: 100,
      ),
      const InstalledModel(
        name: 'second.gguf',
        repository: 'team/second',
        filename: 'second.gguf',
        path: r'C:\models\second.gguf',
        sizeBytes: 200,
      ),
    ];
    InstalledModel? selectedModel;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalModelPicker(
            models: models,
            selectedPath: models.first.path,
            enabled: true,
            onSelected: (model) => selectedModel = model,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('second.gguf · team/second').last);
    await tester.pumpAndSettle();

    expect(selectedModel, same(models.last));
  });
}
