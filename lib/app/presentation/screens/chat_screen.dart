import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app_controller.dart';
import '../../app_theme.dart';
import '../../models/chat_message.dart';
import '../app_destination.dart';
import '../widgets/app_widgets.dart';
import '../widgets/local_model_picker.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.controller,
    required this.onNavigate,
    super.key,
  });

  final AppController controller;
  final ValueChanged<AppDestination> onNavigate;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final TextEditingController _promptController;
  final ScrollController _scrollController = ScrollController();
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController();
    _lastMessageCount = widget.controller.messages.length;
    widget.controller.addListener(_scheduleScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleScroll);
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleScroll() {
    final messageCount = widget.controller.messages.length;
    if (messageCount == _lastMessageCount) return;
    _lastMessageCount = messageCount;
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send([String? suggestion]) {
    final prompt = suggestion ?? _promptController.text;
    final normalizedPrompt = prompt.trim();
    if (normalizedPrompt.isEmpty || widget.controller.isGenerating) return;
    if (normalizedPrompt.length <= 32768) _promptController.clear();
    unawaited(widget.controller.sendPrompt(prompt));
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _ChatToolbar(
        controller: widget.controller,
        onClear: widget.controller.isGenerating
            ? null
            : widget.controller.clearConversation,
      ),
      if (widget.controller.chatMode == ChatMode.local &&
          widget.controller.localModelPath == null)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: InlineNotice(
            message:
                'Load a GGUF model from My models to start a private chat.',
            action: TextButton(
              onPressed: () => widget.onNavigate(AppDestination.library),
              child: const Text('Open library'),
            ),
          ),
        ),
      if (widget.controller.chatMode == ChatMode.remote &&
          !widget.controller.settings.internetEnabled)
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: InlineNotice(
            message:
                'Internet access is off. Turn it on before using a remote API.',
            isError: true,
          ),
        ),
      if (widget.controller.chatMode == ChatMode.local &&
          widget.controller.libraryError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: InlineNotice(
            message: widget.controller.libraryError!,
            isError: true,
          ),
        ),
      if (widget.controller.chatError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: InlineNotice(
            message: widget.controller.chatError!,
            isError: true,
          ),
        ),
      Expanded(
        child: widget.controller.messages.isEmpty
            ? _ChatWelcome(
                controller: widget.controller,
                onPrompt: _send,
                onOpenLibrary: () => widget.onNavigate(AppDestination.library),
              )
            : ListView.builder(
                controller: _scrollController,
                reverse: true,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                itemCount: widget.controller.messages.length,
                itemBuilder: (context, index) {
                  final message = widget
                      .controller
                      .messages[widget.controller.messages.length - 1 - index];
                  return _MessageBubble(
                    message: message,
                    isGenerating:
                        widget.controller.isGenerating &&
                        index == 0 &&
                        message.role == MessageRole.assistant &&
                        message.content.isEmpty,
                  );
                },
              ),
      ),
      _Composer(
        controller: widget.controller,
        promptController: _promptController,
        onSend: _send,
      ),
    ],
  );
}

class _ChatToolbar extends StatelessWidget {
  const _ChatToolbar({required this.controller, required this.onClear});

  final AppController controller;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 18, 20, 16),
    child: Row(
      children: [
        SegmentedButton<ChatMode>(
          segments: const [
            ButtonSegment(
              value: ChatMode.local,
              label: Text('Local'),
              icon: Icon(Icons.memory_rounded),
            ),
            ButtonSegment(
              value: ChatMode.remote,
              label: Text('API'),
              icon: Icon(Icons.language_rounded),
            ),
          ],
          selected: {controller.chatMode},
          onSelectionChanged: controller.isGenerating
              ? null
              : (selection) => controller.setChatMode(selection.first),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: controller.chatMode == ChatMode.local
              ? LocalModelPicker(
                  models: controller.installedModels,
                  selectedPath: controller.localModelPath,
                  enabled:
                      !controller.isLoadingModel &&
                      !controller.isImportingModel &&
                      !controller.isGenerating,
                  isLoading: controller.isLoadingModel,
                  onSelected: (model) {
                    unawaited(controller.loadModel(model));
                  },
                )
              : Text(
                  controller.settings.remoteModel.isEmpty
                      ? 'No API model selected'
                      : controller.settings.remoteModel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
        ),
        if (controller.isLoadingModel)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (controller.isGenerating &&
            controller.chatMode == ChatMode.local)
          TextButton.icon(
            onPressed: controller.cancelGeneration,
            icon: const Icon(Icons.stop_rounded, size: 18),
            label: const Text('Stop'),
          )
        else if (controller.isGenerating)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        IconButton(
          tooltip: 'Clear conversation',
          onPressed: onClear,
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
      ],
    ),
  );
}

class _ChatWelcome extends StatelessWidget {
  const _ChatWelcome({
    required this.controller,
    required this.onPrompt,
    required this.onOpenLibrary,
  });

  final AppController controller;
  final ValueChanged<String> onPrompt;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.raised,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.forum_outlined, color: AppColors.blue),
            ),
            const SizedBox(height: 18),
            Text(
              controller.chatMode == ChatMode.local
                  ? 'Start a local conversation'
                  : 'Connect to your API model',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              controller.chatMode == ChatMode.local
                  ? controller.localModelPath == null
                        ? 'Choose a model from your library. Your prompts stay on this device during local inference.'
                        : 'The model is loaded and ready. Try a prompt below.'
                  : 'Remote messages are sent to the endpoint saved in Settings.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.muted, height: 1.5),
            ),
            if (controller.chatMode == ChatMode.local &&
                controller.localModelPath == null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onOpenLibrary,
                icon: const Icon(Icons.storage_outlined),
                label: const Text('Choose a local model'),
              ),
            ],
            const SizedBox(height: 24),
            for (final prompt in const [
              'Explain how a GGUF model runs locally.',
              'Give me a concise summary of an idea.',
              'Help me outline a small project.',
            ]) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  onPressed:
                      controller.chatMode == ChatMode.local &&
                          controller.localModelPath == null
                      ? null
                      : () => onPrompt(prompt),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: Text(prompt),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isGenerating});

  final ChatMessage message;
  final bool isGenerating;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                const CircleAvatar(
                  radius: 15,
                  backgroundColor: AppColors.raised,
                  child: Icon(
                    Icons.blur_on_rounded,
                    size: 17,
                    color: AppColors.blue,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isUser ? AppColors.raised : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: isGenerating
                      ? const _TypingIndicator()
                      : SelectableText(
                          message.content,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.text, height: 1.5),
                        ),
                ),
              ),
              if (isUser) ...[
                const SizedBox(width: 10),
                const CircleAvatar(
                  radius: 15,
                  backgroundColor: AppColors.blue,
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 17,
                    color: AppColors.canvas,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 38,
    height: 18,
    child: Center(child: LinearProgressIndicator(minHeight: 2)),
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.promptController,
    required this.onSend,
  });

  final AppController controller;
  final TextEditingController promptController;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final hasLocalModel = controller.localModelPath != null;
    final canUseChat = controller.chatMode == ChatMode.remote
        ? controller.settings.internetEnabled &&
              controller.settings.remoteModel.isNotEmpty
        : hasLocalModel;
    final isActive = canUseChat && !controller.isGenerating;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SurfacePanel(
                padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: promptController,
                        minLines: 1,
                        maxLines: 4,
                        enabled: isActive,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          labelText: 'Message',
                          hintText: canUseChat
                              ? 'Write a message…'
                              : controller.chatMode == ChatMode.remote
                              ? 'Configure an API model in Settings'
                              : 'Load a local model to begin',
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Send message',
                      onPressed: isActive ? onSend : null,
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                controller.chatMode == ChatMode.local
                    ? 'Local inference · prompts stay on this device'
                    : 'Remote inference · messages are sent to your configured API',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
