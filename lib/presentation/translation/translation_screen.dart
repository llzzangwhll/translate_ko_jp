import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../app/routes.dart';
import 'translation_controller.dart';

class TranslationScreen extends GetView<TranslationController> {
  const TranslationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('한↔일 통역'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Get.toNamed(Routes.history),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Obx(() => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(controller.sourceLanguage.nativeLabel),
                    IconButton(
                      icon: const Icon(Icons.swap_horiz),
                      onPressed: controller.toggleDirection,
                    ),
                    Text(controller.targetLanguage.nativeLabel),
                  ],
                )),
            const SizedBox(height: 12),
            Expanded(
              child: Obx(() => _Panel(
                    title: controller.sourceLanguage.nativeLabel,
                    text: controller.sourceText.value,
                    onSpeak: controller.speakSource,
                  )),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Obx(() => _Panel(
                    title: controller.targetLanguage.nativeLabel,
                    text: controller.isTranslating.value
                        ? '번역 중...'
                        : controller.translatedText.value,
                    onSpeak: controller.speakTranslation,
                    onCopy: controller.copyTranslation,
                  )),
            ),
            const SizedBox(height: 12),
            Obx(() => controller.errorMessage.value.isEmpty
                ? const SizedBox.shrink()
                : Text(controller.errorMessage.value,
                    style: const TextStyle(color: Colors.red))),
            Center(
              child: Obx(() => FloatingActionButton.large(
                    onPressed: controller.toggleListening,
                    backgroundColor:
                        controller.isListening.value ? Colors.red : null,
                    child: Icon(
                        controller.isListening.value ? Icons.stop : Icons.mic),
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String text;
  final VoidCallback? onSpeak;
  final VoidCallback? onCopy;
  const _Panel({
    required this.title,
    required this.text,
    this.onSpeak,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                if (onSpeak != null)
                  IconButton(
                      icon: const Icon(Icons.volume_up), onPressed: onSpeak),
                if (onCopy != null)
                  IconButton(icon: const Icon(Icons.copy), onPressed: onCopy),
              ],
            ),
            Expanded(child: SingleChildScrollView(child: Text(text))),
          ],
        ),
      ),
    );
  }
}
