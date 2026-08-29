// WariMesh — the volunteer's offline assistant (on-device Gemma-3n E2B).
//
// A chat screen over LlmService: shows model status (ready / not
// downloaded), a "load model" step, and a simple message list + composer.
// Answers stream in as tokens arrive from the native side. The model runs
// entirely on the phone — this screen works with zero connectivity.
import 'package:flutter/material.dart';

import '../llm_service.dart';
import '../theme.dart';

class AssistantScreen extends StatefulWidget {
  final LlmService llm;
  const AssistantScreen({super.key, required this.llm});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.llm.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty ||
        widget.llm.busy ||
        widget.llm.status != LlmStatus.ready) {
      return;
    }
    _controller.clear();
    await widget.llm.generate(
      text,
      onDelta: (_) {
        if (mounted) _scrollToBottom();
      },
    );
    if (mounted) _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline assistant'),
        automaticallyImplyLeading: false,
      ),
      body: AnimatedBuilder(
        animation: widget.llm,
        builder: (context, _) {
          return Column(
            children: [
              _StatusBanner(llm: widget.llm),
              Expanded(
                child: widget.llm.history.isEmpty && !widget.llm.busy
                    ? _EmptyState(llm: widget.llm)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        itemCount:
                            widget.llm.history.length +
                            (widget.llm.busy ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i < widget.llm.history.length) {
                            final msg = widget.llm.history[i];
                            return _MessageBubble(message: msg);
                          }
                          return _ThinkingBubble(text: widget.llm.thinkingText);
                        },
                      ),
              ),
              _Composer(
                controller: _controller,
                enabled:
                    widget.llm.status == LlmStatus.ready && !widget.llm.busy,
                onSend: _send,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final LlmService llm;
  const _StatusBanner({required this.llm});

  @override
  Widget build(BuildContext context) {
    final (icon, color, text, action, actionLabel) = switch (llm.status) {
      LlmStatus.noModel => (
        Icons.download_for_offline_outlined,
        AppColors.warning,
        llm.downloading
            ? 'Downloading model… ${(llm.downloadProgress * 100).toStringAsFixed(0)}%'
            : 'Model not downloaded yet',
        llm.downloading
            ? null
            : () async {
                final ok = await llm.downloadModel();
                if (ok) await llm.loadModel();
              },
        'Download',
      ),
      LlmStatus.downloaded => (
        Icons.inventory_2_outlined,
        AppColors.warning,
        'Model downloaded — tap Load model',
        () async {
          await llm.loadModel();
        },
        'Load',
      ),
      LlmStatus.loading => (
        Icons.hourglass_top,
        AppColors.warning,
        'Loading model…',
        null,
        null,
      ),
      LlmStatus.ready => (
        Icons.check_circle_outline,
        AppColors.relayed,
        'Assistant ready · runs fully offline',
        null,
        null,
      ),
      LlmStatus.error => (
        Icons.error_outline,
        AppColors.sos,
        'Assistant error: ${llm.lastError ?? 'unknown'}',
        () async {
          await llm.loadModel();
        },
        'Retry',
      ),
    };
    return Material(
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            if (llm.status == LlmStatus.ready)
              TextButton(
                onPressed: llm.clearHistory,
                child: const Text('Clear'),
              ),
            if (action != null)
              TextButton(
                onPressed: action,
                child: Text(llm.downloading ? '…' : (actionLabel ?? 'Retry')),
              ),
            if (llm.status == LlmStatus.ready)
              PopupMenuButton<String>(
                tooltip: 'Model',
                onSelected: (v) async {
                  if (v == 'delete') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete model?'),
                        content: const Text(
                          'This removes the ~3.7 GB model from the phone. You\'ll need to re-download or re-push it to use the assistant again.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) await llm.deleteModel();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18),
                        SizedBox(width: 10),
                        Text('Delete model'),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final LlmService llm;
  const _EmptyState({required this.llm});

  @override
  Widget build(BuildContext context) {
    final noModel = llm.status == LlmStatus.noModel;
    final downloaded = llm.status == LlmStatus.downloaded;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              noModel
                  ? Icons.download_for_offline_outlined
                  : downloaded
                  ? Icons.inventory_2_outlined
                  : Icons.psychology_alt_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              noModel
                  ? 'Assistant model not installed'
                  : downloaded
                  ? 'Model downloaded'
                  : 'Ask a volunteer question',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              noModel
                  ? 'Tap Download model, then Load model. After that it works with no network — fully on this phone.'
                  : downloaded
                  ? 'One more step: load the model into memory (a few seconds), then it runs offline.'
                  : 'First aid, lost-person search advice, heatstroke, crowd safety — answers generated on this phone, no network needed.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            if (noModel)
              FilledButton.icon(
                onPressed: llm.downloading
                    ? null
                    : () async {
                        final ok = await llm.downloadModel();
                        if (ok) await llm.loadModel();
                      },
                icon: llm.downloading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download),
                label: Text(
                  llm.downloading
                      ? 'Downloading… ${(llm.downloadProgress * 100).toStringAsFixed(0)}%'
                      : 'Download model (3.7 GB)',
                ),
              )
            else if (downloaded)
              FilledButton.icon(
                onPressed: llm.busy ? null : () => llm.loadModel(),
                icon: const Icon(Icons.memory),
                label: const Text('Load model'),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _SuggestionChip(
                    text: 'What do I do for heatstroke?',
                    onTap: () => _ask(context, 'What do I do for heatstroke?'),
                  ),
                  _SuggestionChip(
                    text: 'How do I organize a search?',
                    onTap: () => _ask(
                      context,
                      'How do I organize a search for a missing person?',
                    ),
                  ),
                  _SuggestionChip(
                    text: 'Crowd crush safety',
                    onTap: () =>
                        _ask(context, 'How do I stay safe in a crowd crush?'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _ask(BuildContext context, String q) {
    final state = context.findAncestorStateOfType<_AssistantScreenState>();
    state?._controller.text = q;
  }
}

class _SuggestionChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _SuggestionChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(label: Text(text), onPressed: onTap);
  }
}

class _MessageBubble extends StatelessWidget {
  final LlmMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.lostPerson
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  final String text;
  const _ThinkingBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text.isEmpty ? 'Thinking…' : text,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Ask about first aid, search, safety…',
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.arrow_upward),
              tooltip: 'Send',
            ),
          ],
        ),
      ),
    );
  }
}
