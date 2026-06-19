import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../domain/entities/translation_result.dart';
import 'history_controller.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<HistoryController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('번역 히스토리'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: '전체 삭제',
            onPressed: () => _confirmClearAll(context, controller),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        final error = controller.errorMessage.value;
        if (error != null && controller.entries.isEmpty) {
          return Center(child: Text(error));
        }
        if (controller.entries.isEmpty) {
          return const Center(child: Text('히스토리가 없습니다'));
        }
        return Column(
          children: [
            if (error != null)
              Container(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Text(
                          error,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: '닫기',
                      onPressed: () => controller.errorMessage.value = null,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.separated(
                itemCount: controller.entries.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = controller.entries[index];
                  return _HistoryTile(entry: entry, controller: controller);
                },
              ),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _confirmClearAll(
    BuildContext context,
    HistoryController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('전체 삭제'),
        content: const Text('모든 번역 히스토리를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.clearAll();
    }
  }
}

class _HistoryTile extends StatelessWidget {
  final TranslationResult entry;
  final HistoryController controller;

  const _HistoryTile({required this.entry, required this.controller});

  String get _directionLabel =>
      '${entry.direction.from.nativeLabel} → ${entry.direction.to.nativeLabel}';

  String get _timestamp {
    final d = entry.createdAt;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _directionLabel,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              Text(
                _timestamp,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(entry.sourceText),
          const SizedBox(height: 2),
          Text(
            entry.translatedText,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: '복사',
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: entry.translatedText),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.volume_up),
                tooltip: '재생',
                onPressed: () => controller.play(entry),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '삭제',
                onPressed: () {
                  final id = entry.id;
                  if (id != null) controller.deleteEntry(id);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
