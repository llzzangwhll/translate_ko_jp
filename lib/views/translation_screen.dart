import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/translation_controller.dart';

class TranslationScreen extends StatelessWidget {
  const TranslationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(TranslationController());
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('한일 번역기'),
        centerTitle: true,
        backgroundColor: colorScheme.primaryContainer,
        actions: [
          Obx(() {
            if (c.isLoadingModel.value) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                c.isModelLoaded.value ? Icons.check_circle : Icons.error,
                color: c.isModelLoaded.value ? Colors.green : Colors.red,
              ),
            );
          }),
        ],
      ),
      body: Column(
        children: [
          // Status banner
          Obx(() {
            if (c.isModelLoaded.value) return const SizedBox.shrink();
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: c.isLoadingModel.value
                  ? Colors.orange.withAlpha(50)
                  : Colors.red.withAlpha(50),
              child: Text(
                c.statusMessage.value,
                style: TextStyle(
                  fontSize: 13,
                  color: c.isLoadingModel.value
                      ? Colors.orange[800]
                      : Colors.red[800],
                ),
                textAlign: TextAlign.center,
              ),
            );
          }),

          // Language toggle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Obx(() => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LanguageChip(
                    label: c.isKoToJp.value ? '한국어' : '日本語',
                    color: colorScheme.primary),
                IconButton(
                  onPressed: c.toggleDirection,
                  icon: const Icon(Icons.swap_horiz, size: 32),
                  color: colorScheme.primary,
                ),
                _LanguageChip(
                    label: c.isKoToJp.value ? '日本語' : '한국어',
                    color: colorScheme.secondary),
              ],
            )),
          ),

          // Source & translation cards
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Expanded(child: _SourceCard(controller: c)),
                  const SizedBox(height: 12),
                  Expanded(child: _TranslationCard(controller: c)),
                ],
              ),
            ),
          ),

          // Bottom action bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Obx(() => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: FloatingActionButton(
                      heroTag: 'mic',
                      onPressed: c.toggleListening,
                      backgroundColor: c.isListening.value
                          ? Colors.red
                          : colorScheme.primaryContainer,
                      child: Icon(
                        c.isListening.value ? Icons.stop : Icons.mic,
                        size: 36,
                        color: c.isListening.value
                            ? Colors.white
                            : colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: FloatingActionButton(
                      heroTag: 'translate',
                      onPressed:
                          (c.isTranslating.value || !c.isModelLoaded.value)
                              ? null
                              : c.translate,
                      backgroundColor: colorScheme.primary,
                      child: Icon(
                        Icons.translate,
                        size: 36,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ],
              )),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  final String label;
  final Color color;

  const _LanguageChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(75)),
      ),
      child: Text(label,
          style:
              TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _SourceCard extends StatelessWidget {
  final TranslationController controller;

  const _SourceCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final c = controller;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Obx(() => Row(
              children: [
                Text(c.sourceLanguage,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary)),
                const Spacer(),
                if (c.textController.text.isNotEmpty) ...[
                  IconButton(
                    icon: const Icon(Icons.volume_up, size: 20),
                    onPressed: c.speakSource,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: c.clear,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            )),
            Expanded(
              child: Obx(() => TextField(
                controller: c.textController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: '${c.sourceLanguage} 텍스트 입력 또는 마이크 사용',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.grey[400]),
                ),
                style: const TextStyle(fontSize: 18),
                onSubmitted: (_) => c.translate(),
              )),
            ),
          ],
        ),
      ),
    );
  }
}

class _TranslationCard extends StatelessWidget {
  final TranslationController controller;

  const _TranslationCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final c = controller;

    return Card(
      elevation: 1,
      color: colorScheme.secondaryContainer.withAlpha(75),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Obx(() => Row(
              children: [
                Text(c.targetLanguage,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.secondary)),
                const Spacer(),
                if (c.translatedText.value.isNotEmpty) ...[
                  IconButton(
                    icon: const Icon(Icons.volume_up, size: 20),
                    onPressed: c.speakTranslation,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: c.copyTranslation,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            )),
            Expanded(
              child: Obx(() {
                if (c.isTranslating.value) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('번역 중...'),
                      ],
                    ),
                  );
                }
                return SingleChildScrollView(
                  child: SelectableText(
                    c.translatedText.value,
                    style: const TextStyle(fontSize: 18),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
