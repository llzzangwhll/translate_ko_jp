import '../../core/result.dart';
import '../../data/repositories/translation_repository.dart';

/// Warms up the inference engine (runs a throwaway inference) so the user's
/// first real translation isn't slowed by one-time engine initialization.
class WarmUpModel {
  final TranslationRepository _repository;
  WarmUpModel(this._repository);

  Future<Result<void>> call() => _repository.warmUp();
}
