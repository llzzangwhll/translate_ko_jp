import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'services/gemma_service.dart';
import 'views/model_setup_screen.dart';
import 'views/translation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register global service
  Get.put(GemmaService());

  // Check if model exists to decide initial route
  final gemma = Get.find<GemmaService>();
  final modelExists = await gemma.checkModelExists();

  runApp(TranslateApp(initialRoute: modelExists ? '/translate' : '/setup'));
}

class TranslateApp extends StatelessWidget {
  final String initialRoute;

  const TranslateApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: '한일 번역기',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: initialRoute,
      getPages: [
        GetPage(name: '/setup', page: () => const ModelSetupScreen()),
        GetPage(name: '/translate', page: () => const TranslationScreen()),
      ],
    );
  }
}
