import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../presentation/setup/setup_screen.dart';
import '../presentation/translation/translation_screen.dart';
import '../presentation/history/history_screen.dart';
import 'routes.dart';

class TranslateApp extends StatelessWidget {
  final String initialRoute;
  const TranslateApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: '한일 통역기',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2563EB), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      initialRoute: initialRoute,
      getPages: [
        GetPage(name: Routes.setup, page: () => const SetupScreen()),
        GetPage(name: Routes.translation, page: () => const TranslationScreen()),
        GetPage(name: Routes.history, page: () => const HistoryScreen()),
      ],
    );
  }
}
