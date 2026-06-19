import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:translate_ko_jp/data/services/tts_service.dart';
import 'package:translate_ko_jp/data/services/history_store.dart';
import 'package:translate_ko_jp/data/repositories/history_repository.dart';
import 'package:translate_ko_jp/domain/usecases/save_translation.dart';
import 'package:translate_ko_jp/domain/usecases/get_history.dart';
import 'package:translate_ko_jp/domain/usecases/delete_history_entry.dart';
import 'package:translate_ko_jp/domain/usecases/clear_history.dart';
import 'package:translate_ko_jp/presentation/history/history_controller.dart';
import 'package:translate_ko_jp/app/history_deps.dart';

import '../fakes/fake_tts_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    Get.put<TtsService>(FakeTtsService());
  });

  tearDown(Get.reset);

  test('registerHistoryDeps wires store, repo, usecases, controller', () async {
    await registerHistoryDeps(databasePath: inMemoryDatabasePath);

    expect(Get.isRegistered<HistoryStore>(), isTrue);
    expect(Get.isRegistered<HistoryRepository>(), isTrue);
    expect(Get.isRegistered<SaveTranslation>(), isTrue);
    expect(Get.isRegistered<GetHistory>(), isTrue);
    expect(Get.isRegistered<DeleteHistoryEntry>(), isTrue);
    expect(Get.isRegistered<ClearHistory>(), isTrue);

    final save = Get.find<SaveTranslation>();
    final controller = Get.find<HistoryController>();
    expect(save, isA<SaveTranslation>());
    expect(controller, isA<HistoryController>());
  });
}
