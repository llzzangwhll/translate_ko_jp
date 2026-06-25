import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'ocr_controller.dart';

/// Photo OCR translation screen.
///
/// The user picks the translation direction, snaps a photo (or picks one from
/// the album), and the recognized text is translated immediately.
class OcrScreen extends StatelessWidget {
  const OcrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<OcrController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('사진 번역'),
        actions: [_AutoSpeakToggle(controller: controller)],
      ),
      body: Column(
        children: [
          _DirectionSelector(controller: controller),
          Expanded(
            child: Obx(() {
              final path = controller.imagePath.value;
              final recognized = controller.recognizedText.value;
              final translated = controller.translatedText.value;
              final processing = controller.isProcessing.value;

              if (path == null && !processing) {
                return const _EmptyState();
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  if (path != null) _ImagePreview(path: path),
                  if (processing)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (recognized.isNotEmpty)
                    _ResultCard(
                      label: controller.sourceLanguage.nativeLabel,
                      text: recognized,
                      emphasized: false,
                      onCopy: () => controller.copyText(recognized),
                    ),
                  if (translated.isNotEmpty)
                    _ResultCard(
                      label: controller.targetLanguage.nativeLabel,
                      text: translated,
                      emphasized: true,
                      onCopy: () => controller.copyText(translated),
                      onSpeak: controller.speakTranslation,
                    ),
                ],
              );
            }),
          ),
          _ErrorArea(controller: controller),
          _ActionBar(controller: controller),
        ],
      ),
    );
  }
}

class _AutoSpeakToggle extends StatelessWidget {
  final OcrController controller;
  const _AutoSpeakToggle({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final on = controller.autoSpeak.value;
      return Row(
        children: [
          Icon(on ? Icons.volume_up : Icons.volume_off, size: 18),
          Switch(
            value: on,
            onChanged: (v) => controller.autoSpeak.value = v,
          ),
        ],
      );
    });
  }
}

class _DirectionSelector extends StatelessWidget {
  final OcrController controller;
  const _DirectionSelector({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Obx(() {
        final dir = controller.direction.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(dir.from.nativeLabel,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              tooltip: '번역 방향 전환',
              onPressed: controller.isProcessing.value
                  ? null
                  : controller.toggleDirection,
            ),
            Text(dir.to.nativeLabel,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        );
      }),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 32, 40, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_camera_outlined,
                size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              '사진 속 문자를 번역해요',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '번역 방향을 고르고 아래에서\n카메라로 촬영하거나 앨범에서 사진을 선택하세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.6,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final String path;
  const _ImagePreview({required this.path});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: Image.file(
            File(path),
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String label;
  final String text;
  final bool emphasized;
  final VoidCallback onCopy;
  final VoidCallback? onSpeak;
  const _ResultCard({
    required this.label,
    required this.text,
    required this.emphasized,
    required this.onCopy,
    this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = emphasized ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final fg = emphasized ? scheme.onPrimaryContainer : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: fg.withAlpha(160)),
            ),
            const SizedBox(height: 6),
            SelectableText(
              text,
              style: TextStyle(
                fontSize: emphasized ? 18 : 15,
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
                color: fg,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onSpeak != null)
                  _CardAction(
                    icon: Icons.volume_up,
                    tooltip: '재생',
                    color: fg.withAlpha(160),
                    onPressed: onSpeak!,
                  ),
                _CardAction(
                  icon: Icons.copy,
                  tooltip: '복사',
                  color: fg.withAlpha(160),
                  onPressed: onCopy,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;
  const _CardAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      color: color,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
      onPressed: onPressed,
    );
  }
}

class _ErrorArea extends StatelessWidget {
  final OcrController controller;
  const _ErrorArea({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final message = controller.errorMessage.value;
      if (message.isEmpty) return const SizedBox.shrink();
      return Container(
        width: double.infinity,
        color: scheme.errorContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            if (controller.permissionPermanentlyDenied.value)
              TextButton(
                onPressed: controller.openAppSettings,
                child: const Text('설정 열기'),
              ),
          ],
        ),
      );
    });
  }
}

class _ActionBar extends StatelessWidget {
  final OcrController controller;
  const _ActionBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Obx(() {
          final busy = controller.isProcessing.value;
          return Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : controller.captureFromCamera,
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('카메라'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: busy ? null : controller.pickFromGallery,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('앨범'),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
