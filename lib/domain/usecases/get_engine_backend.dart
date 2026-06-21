import '../../data/repositories/translation_repository.dart';

/// Reports which backend the inference engine is running on ('gpu', 'cpu',
/// 'none', 'unknown'). Used to show the user whether GPU acceleration is active.
class GetEngineBackend {
  final TranslationRepository _repository;
  GetEngineBackend(this._repository);

  Future<String> call() => _repository.activeBackend();
}
