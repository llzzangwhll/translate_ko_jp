import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:translate_ko_jp/app/app.dart';
import 'package:translate_ko_jp/app/routes.dart';
import 'package:translate_ko_jp/app/translation_deps.dart';
import 'package:translate_ko_jp/app/model_deps.dart';

void main() {
  // Setup route needs only the (sync) translation + model deps; history opens
  // a DB asynchronously and is exercised in its own flow tests instead.
  testWidgets('app boots to setup route without crashing', (tester) async {
    registerTranslationDeps();
    registerModelDeps();

    await tester.pumpWidget(const TranslateApp(initialRoute: Routes.setup));
    await tester.pump();

    expect(find.byType(TranslateApp), findsOneWidget);
    Get.reset();
  });
}
