import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../app/routes.dart';
import '../../core/language.dart';
import '../../domain/entities/translation_result.dart';
import 'translation_controller.dart';

/// Face-to-face conversation interpreting screen.
///
/// The exchange is shown as a chat log (Korean turns on the left, Japanese on
/// the right). Each speaker taps their own mic at the bottom, so there is no
/// need to flip the direction manually between turns.
class TranslationScreen extends StatefulWidget {
  const TranslationScreen({super.key});

  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen> {
  final TranslationController controller = Get.find<TranslationController>();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Keep the newest turn visible as the conversation grows.
    ever<List<TranslationResult>>(controller.messages, (_) => _scrollToEnd());
    ever<bool>(controller.isListening, (_) => _scrollToEnd());
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('대화 통역'),
        actions: [
          _AutoSpeakToggle(controller: controller),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '히스토리',
            onPressed: () => Get.toNamed(Routes.history),
          ),
          Obx(() => IconButton(
                icon: const Icon(Icons.delete_sweep),
                tooltip: '대화 지우기',
                onPressed: controller.messages.isEmpty
                    ? null
                    : controller.clearConversation,
              )),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Obx(() {
              final messages = controller.messages;
              final listening = controller.isListening.value;
              final translating = controller.isTranslating.value;
              final hasLiveBubble = listening || translating;

              if (messages.isEmpty && !hasLiveBubble) {
                return _EmptyState(controller: controller);
              }

              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                itemCount: messages.length + (hasLiveBubble ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index < messages.length) {
                    return _MessageBubble(
                      entry: messages[index],
                      controller: controller,
                    );
                  }
                  return _LiveBubble(
                    isKoSpeaker:
                        controller.direction.value.from == Language.ko,
                    text: controller.sourceText.value,
                    translating: translating,
                  );
                },
              );
            }),
          ),
          _ErrorArea(controller: controller),
          _MicBar(controller: controller),
        ],
      ),
    );
  }
}

class _AutoSpeakToggle extends StatelessWidget {
  final TranslationController controller;
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

class _EmptyState extends StatelessWidget {
  final TranslationController controller;
  const _EmptyState({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 32, 40, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '대화를 시작해 보세요',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '아래에서 말할 언어의 마이크를 누르고\n상대방과 번갈아 이야기하세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.6,
                  ),
            ),
            const SizedBox(height: 28),
            _WarmUpButton(controller: controller),
            const SizedBox(height: 16),
            _BackendBadge(controller: controller),
          ],
        ),
      ),
    );
  }
}

/// Small diagnostic chip showing whether the inference engine is running on
/// the GPU or fell back to the CPU. Helps explain translation speed.
class _BackendBadge extends StatelessWidget {
  final TranslationController controller;
  const _BackendBadge({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final b = controller.engineBackend.value;
      if (b.isEmpty || b == 'none') return const SizedBox.shrink();
      final isGpu = b == 'gpu';
      final label = isGpu
          ? 'GPU 가속 사용 중'
          : b == 'cpu'
              ? 'CPU 사용 중 (느림)'
              : '엔진: $b';
      final color = isGpu ? scheme.primary : scheme.error;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isGpu ? Icons.memory : Icons.warning_amber_rounded,
              size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      );
    });
  }
}

/// Optional one-tap warm-up shown before the first translation. Running it
/// pays the engine's one-time init cost up front so the first real translation
/// responds quickly. Becomes a "준비 완료" confirmation once done.
class _WarmUpButton extends StatelessWidget {
  final TranslationController controller;
  const _WarmUpButton({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      if (controller.warmedUp.value) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              '번역 준비 완료',
              style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
            ),
          ],
        );
      }
      final warming = controller.isWarmingUp.value;
      return FilledButton.tonalIcon(
        onPressed: warming ? null : controller.warmUp,
        icon: warming
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.bolt, size: 18),
        label: Text(warming ? '워밍업 중' : '미리 워밍업'),
      );
    });
  }
}

class _MessageBubble extends StatelessWidget {
  final TranslationResult entry;
  final TranslationController controller;
  const _MessageBubble({required this.entry, required this.controller});

  bool get _isKoSpeaker => entry.direction.from == Language.ko;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isKo = _isKoSpeaker;

    final bubbleColor =
        isKo ? scheme.surfaceContainerHighest : scheme.primaryContainer;
    final translatedColor =
        isKo ? scheme.onSurface : scheme.onPrimaryContainer;
    final radius = Radius.circular(16);
    final shape = BorderRadius.only(
      topLeft: radius,
      topRight: radius,
      bottomLeft: isKo ? const Radius.circular(4) : radius,
      bottomRight: isKo ? radius : const Radius.circular(4),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment:
            isKo ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              entry.direction.from.nativeLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 3),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Container(
              decoration: BoxDecoration(color: bubbleColor, borderRadius: shape),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.sourceText,
                    style: TextStyle(
                      fontSize: 14,
                      color: translatedColor.withAlpha(150),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.translatedText,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: translatedColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BubbleAction(
                        icon: Icons.volume_up,
                        tooltip: '재생',
                        color: translatedColor.withAlpha(160),
                        onPressed: () => controller.speakMessage(entry),
                      ),
                      _BubbleAction(
                        icon: Icons.copy,
                        tooltip: '복사',
                        color: translatedColor.withAlpha(160),
                        onPressed: () =>
                            controller.copyText(entry.translatedText),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;
  const _BubbleAction({
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

class _LiveBubble extends StatelessWidget {
  final bool isKoSpeaker;
  final String text;
  final bool translating;
  const _LiveBubble({
    required this.isKoSpeaker,
    required this.text,
    required this.translating,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = translating ? '번역 중…' : '듣고 있어요…';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: isKoSpeaker ? Alignment.centerLeft : Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withAlpha(120),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      translating ? Icons.translate : Icons.mic,
                      size: 14,
                      color: translating ? scheme.primary : scheme.error,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(text, style: const TextStyle(fontSize: 16)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorArea extends StatelessWidget {
  final TranslationController controller;
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

class _MicBar extends StatelessWidget {
  final TranslationController controller;
  const _MicBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Obx(() {
          final active = controller.activeSource;
          final listening = controller.isListening.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MicButton(
                language: Language.ko,
                isActive: active == Language.ko,
                // While listening on one side, the other mic is disabled to
                // keep the turn-taking unambiguous.
                isDisabled: listening && active != Language.ko,
                onPressed: () => controller.toggleListenFor(Language.ko),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Icon(Icons.swap_horiz, size: 22),
              ),
              _MicButton(
                language: Language.ja,
                isActive: active == Language.ja,
                isDisabled: listening && active != Language.ja,
                onPressed: () => controller.toggleListenFor(Language.ja),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final Language language;
  final bool isActive;
  final bool isDisabled;
  final VoidCallback onPressed;
  const _MicButton({
    required this.language,
    required this.isActive,
    required this.isDisabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Color bg;
    final Color fg;
    if (isActive) {
      bg = scheme.error;
      fg = scheme.onError;
    } else if (isDisabled) {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant.withAlpha(100);
    } else {
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: '${language.nativeLabel} 마이크',
          child: Material(
            color: bg,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: isDisabled ? null : onPressed,
              child: SizedBox(
                width: 68,
                height: 68,
                child: Icon(isActive ? Icons.stop : Icons.mic,
                    size: 32, color: fg),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          language.nativeLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isDisabled ? scheme.onSurfaceVariant.withAlpha(120) : null,
          ),
        ),
      ],
    );
  }
}
