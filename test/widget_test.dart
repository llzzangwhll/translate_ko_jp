import 'package:flutter_test/flutter_test.dart';
import 'package:translate_ko_jp/main.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const TranslateApp(initialRoute: '/setup'));
    expect(find.text('모델 설정'), findsOneWidget);
  });
}
