// WariMesh — Dindi chat and volunteer advisories.
//
// Text over a BLE advertising mesh is a genuinely constrained medium: every
// message is cut into ~24-byte fragments, put on the air one at a time, and
// reassembled by whoever hears them (see TextHeadPacket in models.dart).
// That shapes this screen more than any visual choice does:
//
//  - Messages are capped at kMaxTextLength and the counter is always
//    visible, because length is airtime, not just pixels.
//  - Delivery is best-effort with no acknowledgement. Nothing here claims a
//    message was received — there are no ticks, and there never should be,
//    because this transport genuinely cannot know.
//  - The privacy banner is not boilerplate. A BLE advertisement is public
//    and unencrypted; anyone in range with a scanner reads every word. That
//    has to be said plainly, once, where people will see it.
import 'package:flutter/material.dart';

import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';

class ChatScreen extends StatefulWidget {
  final MeshService mesh;
  final UserProfile profile;

  const ChatScreen({super.key, required this.mesh, required this.profile});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _asAdvisory = false;
  bool _sending = false;

  /// Only volunteers may broadcast an advisory. A warkari talking to their
  /// own Dindi is ordinary conversation; an announcement reaches every
  /// phone in range regardless of group, and that reach belongs with the
  /// people coordinating the route.
  bool get _canAnnounce => widget.profile.role == UserRole.volunteer;

  @override
  void initState() {
    super.initState();
    widget.mesh.markMessagesRead();
    widget.mesh.addListener(_onMesh);
  }

  @override
  void dispose() {
    widget.mesh.removeListener(_onMesh);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onMesh() {
    widget.mesh.markMessagesRead();
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final wasAdvisory = _asAdvisory;
    final ok = await widget.mesh.sendText(
      text,
      announcement: wasAdvisory && _canAnnounce,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) _controller.clear();
    });
    _scrollToEnd();
    if (!ok) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Saved here, but it could not go on the air — check Bluetooth',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.mesh,
      builder: (context, _) {
        final messages = widget.mesh.messages;
        final hasDindi =
            widget.profile.groupOrId.isNotEmpty &&
            widget.profile.groupOrId != '—';

        return Column(
          children: [
            _Header(profile: widget.profile, hasDindi: hasDindi),
            Expanded(
              child: messages.isEmpty
                  ? _EmptyState(hasDindi: hasDindi)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      itemCount: messages.length,
                      itemBuilder: (context, i) =>
                          _MessageBubble(message: messages[i]),
                    ),
            ),
            _Composer(
              controller: _controller,
              sending: _sending,
              canAnnounce: _canAnnounce,
              asAdvisory: _asAdvisory,
              enabled: hasDindi || _canAnnounce,
              onToggleAdvisory: (v) => setState(() => _asAdvisory = v),
              onSend: _send,
              onChanged: () => setState(() {}),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final UserProfile profile;
  final bool hasDindi;
  const _Header({required this.profile, required this.hasDindi});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.forum_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasDindi ? profile.groupOrId : 'No Dindi yet',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.lock_open,
                size: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Anyone nearby with the app can read these — not private',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasDindi;
  const _EmptyState({required this.hasDindi});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              hasDindi ? 'No messages yet' : 'Join a Dindi to start talking',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              hasDindi
                  ? 'Messages travel phone to phone over Bluetooth. Keep them short — every word is airtime.'
                  : 'Set your Dindi from the Home tab, then everyone walking with you can be reached here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MeshTextMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    // An advisory is deliberately not a chat bubble. It comes from a
    // volunteer, applies to everyone in range rather than one Dindi, and
    // should be distinguishable at a glance from someone's chatter.
    if (message.isAnnouncement) return _AdvisoryCard(message: message);

    final mine = message.outgoing;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine
              ? AppColors.relayed.withValues(alpha: 0.15)
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(
                message.displayName,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: AppColors.relayed,
                ),
              ),
            if (!mine) const SizedBox(height: 2),
            Text(message.body, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 3),
            Text(
              TimeOfDay.fromDateTime(message.createdAt).format(context),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _AdvisoryCard extends StatelessWidget {
  final MeshTextMessage message;
  const _AdvisoryCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign, size: 18, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ADVISORY · ${message.displayName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    letterSpacing: 0.7,
                    color: AppColors.warning,
                  ),
                ),
              ),
              Text(
                TimeOfDay.fromDateTime(message.createdAt).format(context),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message.body,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final bool canAnnounce;
  final bool asAdvisory;
  final bool enabled;
  final ValueChanged<bool> onToggleAdvisory;
  final VoidCallback onSend;
  final VoidCallback onChanged;

  const _Composer({
    required this.controller,
    required this.sending,
    required this.canAnnounce,
    required this.asAdvisory,
    required this.enabled,
    required this.onToggleAdvisory,
    required this.onSend,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final used = controller.text.characters.length;
    final over = used > kMaxTextLength;
    // Fragment count is shown, not hidden, because it's the honest cost of
    // the message: each one is another couple of seconds of radio time.
    final fragments = used <= kTextHeadChars
        ? 1
        : 1 + ((used - kTextHeadChars) / kTextPartChars).ceil();

    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canAnnounce)
            Row(
              children: [
                Switch(
                  value: asAdvisory,
                  onChanged: (v) => onToggleAdvisory(v),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    asAdvisory
                        ? 'Advisory — goes to every phone in range, not just your Dindi'
                        : 'Send as advisory to everyone in range',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: asAdvisory ? AppColors.warning : null,
                      fontWeight: asAdvisory ? FontWeight.w700 : null,
                    ),
                  ),
                ),
              ],
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled && !sending,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: enabled ? 'Short message…' : 'Join a Dindi first',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    counterText: '',
                    helperText: used == 0
                        ? null
                        : over
                        ? '$used / $kMaxTextLength — too long'
                        : '$used / $kMaxTextLength · $fragments fragment${fragments == 1 ? '' : 's'}',
                    helperStyle: TextStyle(color: over ? AppColors.sos : null),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: asAdvisory
                        ? AppColors.warning
                        : AppColors.relayed,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: (!enabled || sending || used == 0 || over)
                      ? null
                      : onSend,
                  icon: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          asAdvisory ? Icons.campaign : Icons.send,
                          color: Colors.white,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
