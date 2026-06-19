import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../data/services/history_store.dart';
import '../data/services/sqflite_history_store.dart';
import '../data/services/tts_service.dart';
import '../data/repositories/history_repository.dart';
import '../domain/usecases/save_translation.dart';
import '../domain/usecases/get_history.dart';
import '../domain/usecases/delete_history_entry.dart';
import '../domain/usecases/clear_history.dart';
import '../presentation/history/history_controller.dart';

Future<void> registerHistoryDeps({String? databasePath}) async {
  final path = databasePath ??
      p.join(await getDatabasesPath(), 'translate_ko_jp.db');

  final store = SqfliteHistoryStore();
  await store.open(path: path);
  Get.put<HistoryStore>(store, permanent: true);

  Get.put<HistoryRepository>(
    HistoryRepositoryImpl(Get.find<HistoryStore>()),
    permanent: true,
  );

  Get.put<SaveTranslation>(
    SaveTranslation(Get.find<HistoryRepository>()),
    permanent: true,
  );
  Get.put<GetHistory>(
    GetHistory(Get.find<HistoryRepository>()),
    permanent: true,
  );
  Get.put<DeleteHistoryEntry>(
    DeleteHistoryEntry(Get.find<HistoryRepository>()),
    permanent: true,
  );
  Get.put<ClearHistory>(
    ClearHistory(Get.find<HistoryRepository>()),
    permanent: true,
  );

  Get.lazyPut<HistoryController>(
    () => HistoryController(
      getHistory: Get.find<GetHistory>(),
      deleteHistoryEntry: Get.find<DeleteHistoryEntry>(),
      clearHistory: Get.find<ClearHistory>(),
      tts: Get.find<TtsService>(),
    ),
  );
}
