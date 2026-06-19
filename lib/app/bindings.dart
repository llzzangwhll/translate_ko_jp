import 'translation_deps.dart';
import 'model_deps.dart';
import 'history_deps.dart';

/// Registers all flow dependencies in dependency-safe order.
/// translation must run first (owns InferenceService/TtsService that the
/// model and history flows look up). history is async (opens the DB).
Future<void> registerAllDeps() async {
  registerTranslationDeps();
  registerModelDeps();
  await registerHistoryDeps();
}
