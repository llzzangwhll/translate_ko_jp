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
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('모델 설정')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Text(
                        '번역 모델을\n준비할게요',
                        style: textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w600, height: 1.3),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '처음 한 번만 받으면 인터넷 없이\n오프라인으로 통역할 수 있어요.',
                        style: textTheme.bodyLarge
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 28),
                      const _InfoCard(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Obx(() {
                // Reading observables here ensures Obx tracks them.
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
      ),
    );
  }
}

/// Full-width summary of what will be downloaded — clean info rows, no mascot.
class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.translate,
            label: '모델',
            valueWidget: const _ModelPairValue(),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          const _InfoRow(
            icon: Icons.cloud_off_outlined,
            label: '동작',
            value: '오프라인 · 온디바이스',
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          const _InfoRow(
            icon: Icons.wifi,
            label: '권장',
            value: 'Wi-Fi 환경',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Plain-text value. Ignored when [valueWidget] is supplied.
  final String? value;

  /// Rich value (e.g. a language pair with an icon). Takes precedence.
  final Widget? valueWidget;
  final bool isLast;
  const _InfoRow({
    required this.icon,
    required this.label,
    this.value,
    this.valueWidget,
    this.isLast = false,
  }) : assert(value != null || valueWidget != null);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
            ),
          ),
          valueWidget ??
              Text(
                value!,
                style:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
        ],
      ),
    );
  }
}

/// Model language pair, e.g. "Gemma · 한 ⇄ 일", using a clean Material swap
/// icon instead of a plain arrow glyph.
class _ModelPairValue extends StatelessWidget {
  const _ModelPairValue();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const textStyle = TextStyle(fontWeight: FontWeight.w500, fontSize: 14);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Gemma · ', style: textStyle),
        const Text('한', style: textStyle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Icon(Icons.swap_horiz_rounded, size: 18, color: scheme.primary),
        ),
        const Text('일', style: textStyle),
      ],
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
    final scheme = Theme.of(context).colorScheme;
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
            const SizedBox(height: 16),
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
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                errorMessage.isEmpty ? '오류가 발생했습니다.' : errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('setup-retry-button'),
              onPressed: c.retry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        );

      case ModelStatus.loaded:
        return const Padding(
          padding: EdgeInsets.all(8),
          child: Center(child: CircularProgressIndicator()),
        );

      case ModelStatus.notDownloaded:
      case ModelStatus.downloaded:
        return FilledButton.icon(
          key: const Key('setup-download-button'),
          onPressed: isBusy ? null : c.startDownload,
          icon: const Icon(Icons.download),
          label: const Text('모델 다운로드'),
        );
    }
  }
}
