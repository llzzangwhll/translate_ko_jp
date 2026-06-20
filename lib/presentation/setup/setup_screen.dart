import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../domain/entities/model_status.dart';
import 'setup_controller.dart';

/// Model setup screen: in-app download with progress, cancel, and retry.
/// Expects a [SetupController] to already be registered in GetX DI
/// (see `registerModelDeps()` / the route binding).
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  String _mb(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SetupController>();
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
            Icon(Icons.record_voice_over_outlined,
                size: 80, color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              '번역 모델 설정',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '한일 번역을 위한 온디바이스 Gemma 모델을 내려받습니다.\n'
              'Wi-Fi 환경을 권장합니다.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Obx(() {
              // Reading observables here ensures Obx tracks them
              final status = c.status.value;
              final isBusy = c.isBusy.value;
              final received = c.receivedBytes.value;
              final total = c.totalBytes.value;
              final error = c.errorMessage.value;
              return _StatusSection(
                controller: c,
                mb: _mb,
                status: status,
                isBusy: isBusy,
                receivedBytes: received,
                totalBytes: total,
                errorMessage: error,
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _StatusSection extends StatelessWidget {
  final SetupController controller;
  final String Function(int) mb;
  final ModelStatus status;
  final bool isBusy;
  final int receivedBytes;
  final int totalBytes;
  final String errorMessage;

  const _StatusSection({
    required this.controller,
    required this.mb,
    required this.status,
    required this.isBusy,
    required this.receivedBytes,
    required this.totalBytes,
    required this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    switch (status) {
      case ModelStatus.downloading:
        final fraction = totalBytes > 0 ? receivedBytes / totalBytes : 0.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: totalBytes > 0
                  ? LinearProgressIndicator(value: fraction, minHeight: 10)
                  : const LinearProgressIndicator(minHeight: 10),
            ),
            const SizedBox(height: 12),
            Text(
              key: const Key('setup-progress-text'),
              totalBytes > 0
                  ? '${mb(receivedBytes)} MB / '
                      '${mb(totalBytes)} MB '
                      '(${(fraction * 100).toStringAsFixed(0)}%)'
                  : '다운로드 준비 중...',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              key: const Key('setup-cancel-button'),
              onPressed: c.cancel,
              icon: const Icon(Icons.close),
              label: const Text('취소'),
            ),
          ],
        );

      case ModelStatus.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                errorMessage.isEmpty ? '오류가 발생했습니다.' : errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red[700], fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('setup-retry-button'),
              onPressed: c.retry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        );

      case ModelStatus.loaded:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        );

      case ModelStatus.notDownloaded:
      case ModelStatus.downloaded:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const Key('setup-download-button'),
                onPressed: isBusy ? null : c.startDownload,
                icon: const Icon(Icons.download),
                label: const Text('모델 다운로드'),
              ),
            ),
          ],
        );
    }
  }
}
