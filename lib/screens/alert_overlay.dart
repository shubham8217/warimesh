// WariMesh — the blocking in-app alert.
//
// A system notification is easy to miss: it slides in, it slides away, and
// on a phone in a pocket in a crowd it may never be seen at all. An SOS is
// not a thing that should be possible to miss, so an alert that arrives
// while the app is open takes over the screen and stays there until the
// person explicitly acknowledges it — no swipe-away, no back button, no
// tap-outside-to-dismiss.
//
// The alert shows everything the mesh actually knows: who sent it (a real
// first name when a presence beacon has told us one — see
// MeshService.nameFor), how many relays it crossed to reach here, and for
// a Lost Person alert the name and age carried by the detail packet (see
// LostPersonDetailPacket in models.dart).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../directions.dart';
import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';

Future<void> showMeshAlert(
  BuildContext context,
  MeshService mesh,
  IncomingAlert alert,
) {
  HapticFeedback.heavyImpact();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    // Rebuilds with the mesh: a Lost Person's name arrives on a separate
    // detail packet that can land after this dialog is already open, and
    // the open alert should fill in rather than stay generic.
    builder: (context) => AnimatedBuilder(
      animation: mesh,
      builder: (context, _) => _AlertDialog(alert: alert),
    ),
  );
}

/// Wraps a shell so any alert the mesh receives takes over the screen.
/// Alerts are shown one at a time, in arrival order, each staying up until
/// acknowledged.
class MeshAlertHost extends StatefulWidget {
  final MeshService mesh;
  final Widget child;

  const MeshAlertHost({super.key, required this.mesh, required this.child});

  @override
  State<MeshAlertHost> createState() => _MeshAlertHostState();
}

class _MeshAlertHostState extends State<MeshAlertHost> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    widget.mesh.addListener(_onMeshChanged);
  }

  @override
  void dispose() {
    widget.mesh.removeListener(_onMeshChanged);
    super.dispose();
  }

  void _onMeshChanged() {
    if (_showing || widget.mesh.pendingAlerts.isEmpty) return;
    _drainQueue();
  }

  Future<void> _drainQueue() async {
    _showing = true;
    try {
      while (mounted && widget.mesh.pendingAlerts.isNotEmpty) {
        await showMeshAlert(
          context,
          widget.mesh,
          widget.mesh.pendingAlerts.first,
        );
        widget.mesh.acknowledgeAlert();
      }
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AlertDialog extends StatelessWidget {
  final IncomingAlert alert;
  const _AlertDialog({required this.alert});

  /// Hands the alert's coordinates to a maps app. Deliberately does NOT
  /// dismiss the alert: someone may tap this, glance at the route, and come
  /// straight back — the alert should still be here, unacknowledged, when
  /// they do. Acknowledging stays an explicit, separate act.
  Future<void> _openDirections(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final opened = await openWalkingDirections(
      alert.senderLatitude!,
      alert.senderLongitude!,
    );
    if (opened || !context.mounted) return;
    messenger?.showSnackBar(
      const SnackBar(
        content: Text(
          'No maps app could open — the coordinates above can be typed in by hand',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = alert.isSos ? AppColors.sos : AppColors.lostPerson;
    final sender = alert.senderName ?? alert.packet.senderLabel;

    // canPop: false — the hardware back button must not dismiss an
    // emergency alert either.
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: sosReasonIsSpecific(alert.packet.reason)
                      ? Text(
                          sosReasonEmoji(alert.packet.reason),
                          style: const TextStyle(fontSize: 40),
                        )
                      : Icon(
                          alert.isSos ? Icons.sos : Icons.person_search,
                          size: 44,
                          color: color,
                        ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                !alert.isSos
                    ? 'MISSING PERSON'
                    : sosReasonIsSpecific(alert.packet.reason)
                    ? '${sosReasonLabel(alert.packet.reason).toUpperCase()} SOS'
                    : 'SOS RECEIVED',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                // What they said is wrong, in a full sentence — this is the
                // screen somebody reads at arm's length while deciding
                // whether to start running.
                !alert.isSos
                    ? 'Someone nearby is looking for a missing person.'
                    : sosReasonIsSpecific(alert.packet.reason)
                    ? 'Someone nearby needs help — ${sosReasonLabel(alert.packet.reason).toLowerCase()}.'
                    : 'Someone nearby needs help right now.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),

              // Where it came from. For an SOS this is the most important
              // thing on the screen after the fact of the alert itself —
              // "someone needs help" is not actionable, "someone needs help
              // 240 m to your north-east" is.
              if (alert.hasLocation) ...[
                _LocationCard(alert: alert, color: color),
                const SizedBox(height: 14),
              ],

              // For a Lost Person alert this is the whole point of the
              // screen — who to actually look for.
              if (!alert.isSos)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: alert.lostName == null
                      ? Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Waiting for their details…',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'LOOK FOR',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                    color: color,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              alert.lostAge == null || alert.lostAge!.isEmpty
                                  ? alert.lostName!
                                  : '${alert.lostName!} · age ${alert.lostAge!}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 19,
                              ),
                            ),
                          ],
                        ),
                ),
              if (!alert.isSos) const SizedBox(height: 14),

              _DetailRow(
                icon: Icons.person_outline,
                label: 'From',
                value: sender,
              ),
              _DetailRow(
                icon: Icons.route_outlined,
                label: 'Reached you',
                value: alert.hops == 0
                    ? 'directly'
                    : 'via ${alert.hops} relay${alert.hops == 1 ? '' : 's'}',
              ),
              _DetailRow(
                icon: Icons.schedule,
                label: 'Received',
                value: TimeOfDay.fromDateTime(alert.receivedAt).format(context),
              ),

              const SizedBox(height: 22),

              // When we know where the alert came from, getting there is the
              // point — so directions are the primary action and
              // acknowledging steps back to a secondary one. Dismissing is
              // still one tap away; it just stops being the thing the eye
              // lands on first.
              if (alert.hasLocation) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: color),
                  icon: const Icon(Icons.directions_walk),
                  label: const Text('Open directions'),
                  onPressed: () => _openDirections(context),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    alert.isSos ? 'I\'ve seen this' : 'Got it — I\'ll look',
                  ),
                ),
              ] else
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: color),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    alert.isSos ? 'I\'ve seen this' : 'Got it — I\'ll look',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the alert came from: how far, which way, and the raw coordinates.
///
/// The direction is a true-north bearing, deliberately written as a compass
/// word ("to your north-east") rather than drawn as an arrow. An arrow on
/// screen reads as "point the phone this way", which would need a
/// magnetometer heading this app doesn't read — so it would be wrong
/// whenever the phone wasn't already facing north. A compass word is
/// something a person can act on correctly with no extra assumptions.
///
/// Coordinates are shown too: they're what someone reads aloud over a radio
/// or types into a maps app, and they stay useful when this phone has no
/// fix of its own and there's no distance to give.
class _LocationCard extends StatelessWidget {
  final IncomingAlert alert;
  final Color color;

  const _LocationCard({required this.alert, required this.color});

  @override
  Widget build(BuildContext context) {
    final distance = alert.distanceLabel;
    final direction = alert.directionLabel;
    final coords =
        '${alert.senderLatitude!.toStringAsFixed(5)}, '
        '${alert.senderLongitude!.toStringAsFixed(5)}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.my_location, size: 22, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SENT FROM',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  distance ?? 'Location received',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                  ),
                ),
                if (direction != null)
                  Text(
                    'to your $direction',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                if (distance == null)
                  Text(
                    "Your phone doesn't know its own position, so there's no distance",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 6),
                SelectableText(
                  coords,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
