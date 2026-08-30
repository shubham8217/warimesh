// WariMesh — dedicated SOS screen. Press-and-hold to confirm (prevents an
// accidental tap from firing an emergency alert), then a clear
// sending → sent animation with the packet details, so it reads well on
// camera regardless of whether real BLE hardware is present.
import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';
import 'help_point_detail_screen.dart';
import 'home_widgets.dart';
import 'sos_reason_sheet.dart';

class SosScreen extends StatefulWidget {
  final MeshService mesh;
  const SosScreen({super.key, required this.mesh});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

enum _SendState { idle, holding, sending, sent }

class _SosScreenState extends State<SosScreen>
    with SingleTickerProviderStateMixin {
  _SendState _state = _SendState.idle;
  double _holdProgress = 0;
  Timer? _holdTimer;
  MeshPacket? _lastSent;
  int _category = kCategorySos;
  int _sentReason = kSosReasonUnspecified;

  static const _holdDuration = Duration(milliseconds: 900);

  void _startHold() {
    if (widget.mesh.onCooldown) return;
    setState(() {
      _state = _SendState.holding;
      _holdProgress = 0;
    });
    const tick = Duration(milliseconds: 30);
    _holdTimer = Timer.periodic(tick, (t) {
      setState(() {
        _holdProgress += tick.inMilliseconds / _holdDuration.inMilliseconds;
      });
      if (_holdProgress >= 1) {
        t.cancel();
        _confirmSend();
      }
    });
  }

  void _cancelHold() {
    if (_state != _SendState.holding) return;
    _holdTimer?.cancel();
    setState(() {
      _state = _SendState.idle;
      _holdProgress = 0;
    });
  }

  Future<void> _confirmSend() async {
    // "What do you need help with?" — see sos_reason_sheet.dart. Only for an
    // SOS: a Lost Person alert's "what" is the person, and it has its own
    // form already. Dismissing the sheet still sends, as unspecified.
    var reason = kSosReasonUnspecified;
    if (_category == kCategorySos) {
      reason = await askSosReason(context);
      if (!mounted) return;
    }

    setState(() {
      _state = _SendState.sending;
      _sentReason = reason;
    });
    final packet = await widget.mesh.sendAlert(_category, reason: reason);
    if (!mounted) return;
    if (packet == null) {
      setState(() => _state = _SendState.idle);
      return;
    }
    setState(() {
      _lastSent = packet;
      _state = _SendState.sent;
    });
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _state = _SendState.idle);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mesh = widget.mesh;
    final color = _category == kCategorySos
        ? AppColors.sos
        : AppColors.lostPerson;

    return Column(
      children: [
        AppBar(title: Text(t.sendAlertTitle), automaticallyImplyLeading: false),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SegmentedButton<int>(
            segments: [
              const ButtonSegment(
                value: kCategorySos,
                label: Text('SOS'),
                icon: Icon(Icons.sos),
              ),
              ButtonSegment(
                value: kCategoryLostPerson,
                label: Text(t.lostPersonAlert),
                icon: Icon(Icons.person_search),
              ),
            ],
            selected: {_category},
            onSelectionChanged: _state == _SendState.idle
                ? (s) => setState(() => _category = s.first)
                : null,
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildButton(color),
                  const SizedBox(height: 28),
                  _buildStatusText(mesh, color),
                ],
              ),
            ),
          ),
        ),
        // "SOS SENT / ✓ Alert propagated to your Dindi / ✓ Alert propagated
        // to nearby volunteers" — see the identical checklist (and its
        // "propagated, not received" caveat) on MyAlertCard in
        // home_widgets.dart, which is where this continues once someone
        // leaves this screen: SOS is never tiered down (see the note in
        // MeshService._handleReceivedPacket), so both are true for every
        // SOS sent, not something worth showing per-category status for.
        if (_lastSent != null &&
            _state == _SendState.sent &&
            _category == kCategorySos)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              children: [
                _SentCheckLine(t.sosPropagatedDindi),
                _SentCheckLine(t.sosPropagatedVolunteers),
                // Seva already discovered through the mesh that matches what
                // is wrong. Shown right here because this is the screen
                // somebody is still looking at in the seconds after pressing
                // SOS — see RelevantSevaCard.
                if (mesh.sevaForReason(_sentReason).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  RelevantSevaCard(
                    reason: _sentReason,
                    seva: mesh.sevaForReason(_sentReason),
                    onTap: (point) => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            HelpPointDetailScreen(mesh: mesh, point: point),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (_lastSent != null && _state != _SendState.sent)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              // Diagnostic tail, kept in Arabic numerals on purpose — this
              // line is for confirming which packet went out, not for a
              // pilgrim mid-emergency. See the note in app_strings.dart.
              '${t.lastSent}: msg #${_lastSent!.msgId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _buildButton(Color color) {
    final onCooldown = widget.mesh.onCooldown && _state == _SendState.idle;
    return GestureDetector(
      onTapDown: (_) => _startHold(),
      onTapUp: (_) => _cancelHold(),
      onTapCancel: _cancelHold,
      child: SizedBox(
        width: 220,
        height: 220,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_state == _SendState.sending)
              const SizedBox(
                width: 220,
                height: 220,
                child: CircularProgressIndicator(strokeWidth: 5),
              ),
            if (_state == _SendState.holding)
              SizedBox(
                width: 220,
                height: 220,
                child: CircularProgressIndicator(
                  value: _holdProgress,
                  strokeWidth: 6,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _state == _SendState.holding ? 178 : 190,
              height: _state == _SendState.holding ? 178 : 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onCooldown ? Colors.grey.shade400 : color,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: _state == _SendState.sent
                    ? const Icon(Icons.check, color: Colors.white, size: 56)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _category == kCategorySos
                                ? Icons.sos
                                : Icons.person_search,
                            color: Colors.white,
                            size: 44,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            onCooldown
                                ? mrNum(
                                    widget.mesh.cooldownRemaining.inSeconds + 1,
                                  )
                                : t.sosHold,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusText(MeshService mesh, Color color) {
    String text;
    switch (_state) {
      case _SendState.idle:
        text = mesh.onCooldown
            ? t.sosCooldown(mesh.cooldownRemaining.inSeconds + 1)
            : _category == kCategorySos
            ? '${t.sosSend} — ${t.holdSuffix}'
            : '${t.lostPersonAlert} — ${t.holdSuffix}';
        break;
      case _SendState.holding:
        text = t.sosKeepHolding;
        break;
      case _SendState.sending:
        text = t.sosSending;
        break;
      case _SendState.sent:
        // The msgId/TTL tail is deliberately dropped from the Marathi
        // headline: it is diagnostic detail, and the person reading this
        // screen has just pressed an emergency button. It remains in the
        // activity log, which is where it belongs.
        text = _category != kCategorySos
            ? '${t.lostPersonAlert} ${t.alertNowSent}'
            : sosReasonIsSpecific(_sentReason)
            ? '${sosReasonEmoji(_sentReason)} ${t.sosReason(_sentReason)} — ${t.sosSent}'
            : t.sosSent;
        break;
    }
    return Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _SentCheckLine extends StatelessWidget {
  final String text;
  const _SentCheckLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check, size: 14, color: AppColors.relayed),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
