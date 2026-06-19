import 'package:get/get.dart';

import '../../core/result.dart';
import '../../domain/entities/translation_result.dart';
import '../../domain/usecases/get_history.dart';
import '../../domain/usecases/delete_history_entry.dart';
import '../../domain/usecases/clear_history.dart';
import '../../data/services/tts_service.dart';

class HistoryController extends GetxController {
  final GetHistory _getHistory;
  final DeleteHistoryEntry _deleteHistoryEntry;
  final ClearHistory _clearHistory;
  final TtsService _tts;

  HistoryController({
    required GetHistory getHistory,
    required DeleteHistoryEntry deleteHistoryEntry,
    required ClearHistory clearHistory,
    required TtsService tts,
  })  : _getHistory = getHistory,
        _deleteHistoryEntry = deleteHistoryEntry,
        _clearHistory = clearHistory,
        _tts = tts;

  final RxList<TranslationResult> entries = <TranslationResult>[].obs;
  final RxBool isLoading = false.obs;
  final RxnString errorMessage = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = null;
    final result = await _getHistory();
    switch (result) {
      case Ok<List<TranslationResult>>(value: final list):
        entries.assignAll(list);
      case Err<List<TranslationResult>>(failure: final f):
        errorMessage.value = f.message;
    }
    isLoading.value = false;
  }

  Future<void> deleteEntry(int id) async {
    final result = await _deleteHistoryEntry(id);
    switch (result) {
      case Ok<void>():
        entries.removeWhere((e) => e.id == id);
      case Err<void>(failure: final f):
        errorMessage.value = f.message;
    }
  }

  Future<void> clearAll() async {
    final result = await _clearHistory();
    switch (result) {
      case Ok<void>():
        entries.clear();
      case Err<void>(failure: final f):
        errorMessage.value = f.message;
    }
  }

  Future<void> play(TranslationResult entry) async {
    await _tts.stop();
    await _tts.speak(
      text: entry.translatedText,
      language: entry.direction.to,
    );
  }
}
