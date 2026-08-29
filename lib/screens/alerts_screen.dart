// WariMesh — the volunteer's response queue.
//
// This screen is the reason "volunteer" is a role and not a skin. A warkari
// generates events: they press SOS, they report someone missing. A volunteer
// absorbs them. Before this screen existed, an incoming alert flashed an
// overlay, dropped a line into the activity log, and was gone — the mesh
// could raise an alarm but had no way to represent "somebody is handling
// this", and no way to say it was over.
//
// So the queue is built around three states and nothing else:
//
//   Open      — nobody has said they're going
//   Claimed   — a named volunteer is responding (ACK on the air)
//   Resolved  — closed, with a reason (RESOLVE on the air)
//
// Ordering is fixed and boring on purpose (see AlertRecord.triageRank):
// unclaimed SOS, unclaimed lost person, claimed, resolved — oldest first
// inside each band. Someone reading this while walking needs the same
// screen every time they look at it, not a helpful reshuffle.
import 'package:flutter/material.dart';

import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class AlertsScreen extends StatelessWidget {
  final MeshService mesh;
  const AlertsScreen({super.key, required this.mesh});

  @override
  Widget build(BuildContext context) {
    final queue = mesh.triagedAlerts.where((a) => !a.mine).toList();
    final open = queue.where((a) => !a.isResolved).length;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: const Text('Response queue'),
          actions: [
            if (open > 0)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: StatusPill(
                    text: '$open open',
                    color: AppColors.sos,
                    icon: Icons.notifications_active_outlined,
                  ),
                ),
              ),
          ],
        ),
        if (queue.isEmpty)
          const SliverFillRemaining(hasScrollBody: false, child: _EmptyQueue())
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            sliver: SliverList.separated(
              itemCount: queue.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) =>
                  AlertQueueCard(alert: queue[i], mesh: mesh),
            ),
          ),
      ],
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 56,
            color: AppColors.relayed.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          const Text(
            'Nothing waiting',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            // Said plainly, because an empty screen in an emergency app is
            // ambiguous in a way that matters: "no alerts" and "not
            // listening" look identical, and only one of them is fine.
            'No alerts have reached this phone. It stays listening in the '
            'background — anything that arrives lands here.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

/// One alert in the queue. The card's whole job is to answer, in the order
/// a responder actually asks them: what happened, to whom, where, how long
/// ago, is anyone on it, and what do I press.
class AlertQueueCard extends StatelessWidget {
  final AlertRecord alert;
  final MeshService mesh;

  const AlertQueueCard({super.key, required this.alert, required this.mesh});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final accent = alert.isSos ? AppColors.sos : AppColors.lostPerson;
    final resolved = alert.isResolved;

    return Opacity(
      // Resolved alerts stay on the list rather than disappearing — a
      // RESOLVE packet is an unsigned claim from an unauthenticated radio
      // (see kResolvePacketType), so the volunteer must be able to see it,
      // question it, and put it back. Faded and sunk to the bottom is the
      // honest treatment; deleted is not.
      opacity: resolved ? 0.6 : 1,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: accent.withValues(alpha: 0.12),
                    child: Icon(
                      alert.isSos ? Icons.sos : Icons.person_search,
                      color: accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert.lostSummary ?? alert.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _sourceLine(),
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                  _StateChip(alert: alert),
                ],
              ),
              const SizedBox(height: 12),
              _LocationLine(alert: alert),
              if (alert.isClaimed) ...[
                const SizedBox(height: 10),
                _ClaimBanner(alert: alert, mesh: mesh),
              ],
              if (resolved) ...[
                const SizedBox(height: 10),
                _ResolvedBanner(alert: alert, mesh: mesh),
              ],
              const SizedBox(height: 14),
              _Actions(alert: alert, mesh: mesh),
            ],
          ),
        ),
      ),
    );
  }

  /// "From Sunita · 1 hop · 4 min ago" — falls back to the raw Mesh ID when
  /// no presence beacon has told us a name, which is common for someone
  /// several hops out.
  String _sourceLine() {
    final who = alert.senderName ?? alert.senderLabel;
    final hops = alert.hops == 0
        ? 'direct'
        : '${alert.hops} hop${alert.hops == 1 ? '' : 's'}';
    return 'From $who · $hops · ${alert.ageLabel}';
  }
}

class _StateChip extends StatelessWidget {
  final AlertRecord alert;
  const _StateChip({required this.alert});

  @override
  Widget build(BuildContext context) {
    if (alert.isResolved) {
      return const StatusPill(
        text: 'Closed',
        color: AppColors.relayed,
        icon: Icons.check,
      );
    }
    if (alert.isClaimed) {
      return const StatusPill(
        text: 'Taken',
        color: AppColors.warning,
        icon: Icons.directions_run,
      );
    }
    return StatusPill(
      text: 'Open',
      color: alert.isSos ? AppColors.sos : AppColors.lostPerson,
      icon: Icons.priority_high,
    );
  }
}

class _LocationLine extends StatelessWidget {
  final AlertRecord alert;
  const _LocationLine({required this.alert});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final distance = alert.distanceLabel;
    final direction = alert.directionLabel;

    final String text;
    final IconData icon;
    if (distance != null && direction != null) {
      text = '$distance, to your $direction';
      icon = Icons.near_me;
    } else if (alert.hasLocation) {
      // We have their coordinates but not our own — say so, rather than
      // showing a distance we cannot compute or hiding the fact entirely.
      text = 'Position known, but this phone has no fix to measure from';
      icon = Icons.location_searching;
    } else {
      text = 'No position — this alert came without one';
      icon = Icons.location_off_outlined;
    }

    return Row(
      children: [
        Icon(icon, size: 16, color: muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}

class _ClaimBanner extends StatelessWidget {
  final AlertRecord alert;
  final MeshService mesh;
  const _ClaimBanner({required this.alert, required this.mesh});

  @override
  Widget build(BuildContext context) {
    final mine = alert.claimedByMe(mesh.myMeshId);
    // "Sunita · Volunteer is responding" / "Rahul · Dindi Lead is
    // coordinating" — see responderRoleLabel()/responderVerb() in
    // models.dart. A volunteer seeing a Lead coordinate their own Dindi's
    // SOS (or vice versa) is exactly the cross-visibility this feature
    // exists for.
    final String who;
    if (mine) {
      who = 'You are responding';
    } else {
      final role = mesh.responderRoleLabelFor(alert.claimedBy!);
      final name = mesh.nameFor(alert.claimedBy!) ?? alert.claimedBy!;
      who = '$name · $role ${responderVerb(role)}';
    }
    return _Banner(
      color: AppColors.warning,
      icon: Icons.directions_run,
      text: who,
    );
  }
}

class _ResolvedBanner extends StatelessWidget {
  final AlertRecord alert;
  final MeshService mesh;
  const _ResolvedBanner({required this.alert, required this.mesh});

  @override
  Widget build(BuildContext context) {
    final by = alert.resolvedBy;
    final who = by == mesh.myMeshId
        ? 'you'
        : (mesh.nameFor(by ?? '') ?? by ?? 'someone');
    return _Banner(
      color: AppColors.relayed,
      icon: Icons.check_circle,
      text:
          '${resolveReasonLabel(alert.resolvedReason ?? kResolveHandled)} — closed by $who',
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _Banner({required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The buttons. Exactly one primary action per state, because a responder
/// deciding between four equally-weighted buttons is a responder standing
/// still.
class _Actions extends StatelessWidget {
  final AlertRecord alert;
  final MeshService mesh;
  const _Actions({required this.alert, required this.mesh});

  @override
  Widget build(BuildContext context) {
    if (alert.isResolved) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => mesh.reopenAlert(alert),
          icon: const Icon(Icons.undo, size: 18),
          label: const Text('Reopen'),
        ),
      );
    }

    final mineToClose = alert.isOpen || alert.claimedByMe(mesh.myMeshId);

    return Row(
      children: [
        if (alert.isOpen)
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: alert.isSos
                    ? AppColors.sos
                    : AppColors.lostPerson,
              ),
              onPressed: () => mesh.claimAlert(alert),
              icon: const Icon(Icons.pan_tool_alt, size: 18),
              label: const Text("I'm responding"),
            ),
          )
        else if (!alert.claimedByMe(mesh.myMeshId))
          // Someone else has it. Joining is allowed but deliberately quiet:
          // the point of ACK is that five volunteers don't converge on one
          // incident while a second goes unanswered.
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => mesh.claimAlert(alert),
              icon: const Icon(Icons.group_add_outlined, size: 18),
              label: const Text('Join anyway'),
            ),
          ),
        if (mineToClose) ...[
          if (alert.isOpen) const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: alert.isOpen ? null : AppColors.relayed,
              ),
              onPressed: () => _close(context),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Close'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _close(BuildContext context) async {
    final reason = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                'Close this alert',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                // Worth stating: closing is not a private bookkeeping act,
                // it puts a packet on the air that stops other phones
                // searching.
                'Nearby phones will be told, and will stop passing this alert on.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.favorite, color: AppColors.relayed),
              title: const Text(
                'Found safe',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('The person is back with their people'),
              onTap: () => Navigator.pop(context, kResolveFound),
            ),
            ListTile(
              leading: const Icon(
                Icons.medical_services_outlined,
                color: AppColors.lostPerson,
              ),
              title: const Text(
                'Handled',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Dealt with — treated, escorted, passed to police',
              ),
              onTap: () => Navigator.pop(context, kResolveHandled),
            ),
            ListTile(
              leading: const Icon(
                Icons.cancel_outlined,
                color: AppColors.neutral,
              ),
              title: const Text(
                'False alarm',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Sent by mistake'),
              onTap: () => Navigator.pop(context, kResolveFalseAlarm),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (reason != null) await mesh.resolveAlert(alert, reason: reason);
  }
}
