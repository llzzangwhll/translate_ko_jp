import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:translate_ko_jp/domain/entities/language_direction.dart';
import 'package:translate_ko_jp/domain/entities/translation_result.dart';
import 'package:translate_ko_jp/domain/usecases/get_history.dart';
import 'package:translate_ko_jp/domain/usecases/delete_history_entry.dart';
import 'package:translate_ko_jp/domain/usecases/clear_history.dart';
import 'package:translate_ko_jp/presentation/history/history_controller.dart';
import 'package:translate_ko_jp/presentation/history/history_screen.dart';

import '../../fakes/fake_history_repository.dart';
import '../../fakes/fake_tts_service.dart';

TranslationResult _entry({required int at, String src = '안녕', String tr = 'やあ'}) =>
    TranslationResult(
      sourceText: src,
      translatedText: tr,
      direction: LanguageDirection.koToJa(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(at),
    );

void main() {
  late FakeHistoryRepository repo;
  late FakeTtsService tts;

  setUp(() {
    repo = FakeHistoryRepository();
    tts = FakeTtsService();
  });

  tearDown(Get.reset);

  Future<void> pump(WidgetTester tester) async {
    Get.put<HistoryController>(HistoryController(
      getHistory: GetHistory(repo),
      deleteHistoryEntry: DeleteHistoryEntry(repo),
      clearHistory: ClearHistory(repo),
      tts: tts,
    ));
    await tester.pumpWidget(const GetMaterialApp(home: HistoryScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('renders entries newest-first with source and translated text',
      (tester) async {
    await repo.save(_entry(at: 1000, src: 'old', tr: 'ふるい'));
    await repo.save(_entry(at: 2000, src: 'new', tr: 'あたらしい'));

    await pump(tester);

    expect(find.text('old'), findsOneWidget);
    expect(find.text('あたらしい'), findsOneWidget);

    final newY = tester.getTopLeft(find.text('new')).dy;
    final oldY = tester.getTopLeft(find.text('old')).dy;
    expect(newY, lessThan(oldY));
  });

  testWidgets('shows empty state when there is no history', (tester) async {
    await pump(tester);
    expect(find.text('히스토리가 없습니다'), findsOneWidget);
  });

  testWidgets('tapping play speaks the translated text', (tester) async {
    await repo.save(_entry(at: 1000, tr: 'やあ'));
    await pump(tester);

    await tester.tap(find.byIcon(Icons.volume_up).first);
    await tester.pump();

    expect(tts.spoken.single.text, 'やあ');
  });

  testWidgets('tapping delete removes the item', (tester) async {
    await repo.save(_entry(at: 1000, src: 'doomed'));
    await pump(tester);
    expect(find.text('doomed'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();

    expect(find.text('doomed'), findsNothing);
  });

  testWidgets('clear-all confirm dialog empties the list', (tester) async {
    await repo.save(_entry(at: 1000, src: 'a'));
    await repo.save(_entry(at: 2000, src: 'b'));
    await pump(tester);

    await tester.tap(find.byIcon(Icons.delete_sweep));
    await tester.pumpAndSettle();

    expect(find.text('전체 삭제'), findsWidgets);
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(find.text('a'), findsNothing);
    expect(find.text('b'), findsNothing);
    expect(repo.clearCount, 1);
  });

  testWidgets(
      'shows inline error banner above list when entries exist and errorMessage is set',
      (tester) async {
    await repo.save(_entry(at: 1000, src: 'hello', tr: 'こんにちは'));
    await repo.save(_entry(at: 2000, src: 'world', tr: 'せかい'));

    Get.put<HistoryController>(HistoryController(
      getHistory: GetHistory(repo),
      deleteHistoryEntry: DeleteHistoryEntry(repo),
      clearHistory: ClearHistory(repo),
      tts: tts,
    ));
    await tester.pumpWidget(const GetMaterialApp(home: HistoryScreen()));
    await tester.pumpAndSettle();

    // Inject error while entries remain
    final controller = Get.find<HistoryController>();
    controller.errorMessage.value = '삭제 실패: disk full';
    await tester.pump();

    // Inline banner is visible
    expect(find.text('삭제 실패: disk full'), findsOneWidget);
    // List items are still rendered
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('world'), findsOneWidget);

    // Dismiss banner via close button
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('삭제 실패: disk full'), findsNothing);
  });
}
