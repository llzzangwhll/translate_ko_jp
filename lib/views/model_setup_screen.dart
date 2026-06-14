import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../controllers/model_setup_controller.dart';

class ModelSetupScreen extends StatelessWidget {
  const ModelSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(ModelSetupController());
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('모델 설정'),
        centerTitle: true,
        backgroundColor: colorScheme.primaryContainer,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.smart_toy_outlined, size: 80, color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              '번역 모델 설정',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '한일 번역을 위한 Gemma 모델이 필요합니다.\n아래 단계를 따라 설정해주세요.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            _StepCard(
              step: 1,
              title: '모델 다운로드',
              icon: Icons.download,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('아래 사이트에서 Gemma 모델을 다운로드하세요:',
                      style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 12),
                  _LinkTile(
                      title: 'Kaggle - Gemma',
                      url: 'kaggle.com/models/google/gemma'),
                  _LinkTile(
                      title: 'Hugging Face - Gemma',
                      url: 'huggingface.co/google/gemma-2b'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withAlpha(100)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Colors.amber),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '권장: gemma-2b-it INT4 양자화 버전\n(MediaPipe용 .bin 또는 .task 파일)',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _StepCard(
              step: 2,
              title: '모델 파일 선택',
              icon: Icons.folder_open,
              child: Obx(() => Column(
                children: [
                  const Text('다운로드한 모델 파일을 선택하세요.\n앱 내부 저장소로 복사됩니다.',
                      style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: c.isBusy.value
                          ? null
                          : () async {
                              if (await c.pickModelFile()) {
                                Get.offAllNamed('/translate');
                              }
                            },
                      icon: const Icon(Icons.file_open),
                      label: const Text('파일 선택'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: c.isBusy.value
                          ? null
                          : () async {
                              if (await c.tryAutoDetect()) {
                                Get.offAllNamed('/translate');
                              }
                            },
                      icon: const Icon(Icons.search),
                      label: const Text('자동 검색 (Download 폴더)'),
                    ),
                  ),
                ],
              )),
            ),
            const SizedBox(height: 24),

            Obx(() {
              if (c.isBusy.value) {
                return Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: c.progress.value > 0
                          ? LinearProgressIndicator(
                              value: c.progress.value, minHeight: 8)
                          : const LinearProgressIndicator(minHeight: 8),
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              }
              return const SizedBox.shrink();
            }),

            Obx(() {
              if (c.status.value.isEmpty) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.isBusy.value
                      ? colorScheme.primaryContainer.withAlpha(80)
                      : Colors.red.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  c.status.value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: c.isBusy.value
                        ? colorScheme.onSurface
                        : Colors.red[700],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final int step;
  final String title;
  final IconData icon;
  final Widget child;

  const _StepCard({
    required this.step,
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: colorScheme.primary,
                  child: Text('$step',
                      style: TextStyle(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
                const SizedBox(width: 10),
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final String title;
  final String url;

  const _LinkTile({required this.title, required this.url});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.language, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(url, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.open_in_new, size: 16),
      onTap: () {
        Clipboard.setData(ClipboardData(text: 'https://$url'));
        Get.snackbar('복사', 'URL이 복사되었습니다',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 1));
      },
    );
  }
}
