import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:translate_ko_jp/domain/entities/model_status.dart';
import 'package:translate_ko_jp/domain/usecases/ensure_model_ready.dart';
import 'package:translate_ko_jp/presentation/setup/setup_controller.dart';
import 'package:translate_ko_jp/presentation/setup/setup_screen.dart';

import '../../fakes/fake_model_repository.dart';

void main() {
  setUp(() => Get.reset());
  tearDown(() => Get.reset());

  SetupController register(FakeModelRepository repo) {
    final controller = SetupController(
      repository: repo,
      ensureModelReady: EnsureModelReady(repo),
      onReady: () {},
    );
    Get.put<SetupController>(controller);
    return controller;
  }

  testWidgets('renders title and download button when notDownloaded',
      (tester) async {
    final repo = FakeModelRepository()..statusValue = ModelStatus.notDownloaded;
    final controller = register(repo);
    controller.status.value = ModelStatus.notDownloaded;

    await tester.pumpWidget(const GetMaterialApp(home: SetupScreen()));
    await tester.pump();

    expect(find.text('번역 모델 설정'), findsOneWidget);
    expect(find.byKey(const Key('setup-download-button')), findsOneWidget);
  });

  testWidgets('shows progress bar and MB text while downloading',
      (tester) async {
    final repo = FakeModelRepository();
    final controller = register(repo);
    controller.status.value = ModelStatus.downloading;
    controller.isBusy.value = true;
    controller.receivedBytes.value = 50 * 1024 * 1024;
    controller.totalBytes.value = 100 * 1024 * 1024;

    await tester.pumpWidget(const GetMaterialApp(home: SetupScreen()));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('setup-progress-text')), findsOneWidget);
    expect(find.textContaining('50'), findsWidgets);
    expect(find.byKey(const Key('setup-cancel-button')), findsOneWidget);
  });

  testWidgets('shows retry button on error', (tester) async {
    final repo = FakeModelRepository();
    final controller = register(repo);
    controller.status.value = ModelStatus.error;
    controller.errorMessage.value = '다운로드 실패: net';

    await tester.pumpWidget(const GetMaterialApp(home: SetupScreen()));
    await tester.pump();

    expect(find.byKey(const Key('setup-retry-button')), findsOneWidget);
    expect(find.textContaining('다운로드 실패'), findsOneWidget);
  });
}
