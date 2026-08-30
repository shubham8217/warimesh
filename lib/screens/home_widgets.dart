// WariMesh — the home-screen furniture shared by both roles.
//
// These started life inside warkari_home_screen.dart. The volunteer
// dashboard was written earlier, never got this layout, and so ended up
// without the Dindi card entirely — a volunteer literally could not join or
// change a Dindi from their own home screen. Rather than copy 300 lines
// across, both screens now build from the same pieces, so the two roles
// can't drift apart again.
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'dindi_picker.dart';

/// Help points heard right now — the volunteer-side feature seen from the
/// pilgrim's side.
///
/// There is no distance and no arrow here, and that is deliberate rather
/// than unfinished. A presence beacon carries no position (see HelpPoint in
/// mesh_service.dart); what stands in for a distance is the physics of the
/// radio. BLE advertising reaches tens of metres in a dense crowd, so
/// hearing this beacon at all means the tent is close enough to walk to.
/// "In range" is the honest claim, and inventing a direction the packet
/// does not contain would send someone the wrong way.
class HelpPointsCard extends StatelessWidget {
  final List<HelpPoint> points;
  const HelpPointsCard({super.key, required this.points});

  static const Map<int, IconData> _icons = {
    kStationMedical: Icons.medical_services,
    kStationWater: Icons.water_drop,
    kStationFood: Icons.restaurant,
    kStationLostChildDesk: Icons.child_care,
    kStationPolice: Icons.local_police,
  };

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.volunteer_activism,
                  color: AppColors.relayed,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  points.length == 1
                      ? 'Help is nearby'
                      : '${points.length} help points nearby',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Close enough for your phone to hear them.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 12),
            for (final point in points) ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.relayed.withValues(alpha: 0.12),
                    child: Icon(
                      _icons[point.station] ?? Icons.help_outline,
                      size: 17,
                      color: AppColors.relayed,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          point.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          point.name.isEmpty
                              ? point.freshnessLabel
                              : '${point.name} · ${point.freshnessLabel}',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (point != points.last) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Nearby Seva" — help points reached over the mesh, potentially several
/// hops from the volunteer who announced them. This is the Wari Seva
/// Network's home-screen face: [HelpPointsCard] above shows what THIS
/// phone's radio can hear right this second (single-hop, no status, no
/// close); this shows the durable, relayed, closeable kind (see
/// HelpPointRecord in models.dart) — which is what actually answers "where
/// is the nearest medical tent" for someone who isn't standing next to it.
///
/// Deliberately calm rather than a dashboard: one icon, one status word, one
/// freshness label per row. "Received through WariMesh" — never a distance,
/// per the same no-location rule as HelpPointsCard.
class NearbySevaCard extends StatelessWidget {
  final List<HelpPointRecord> points;
  final ValueChanged<HelpPointRecord> onTap;

  const NearbySevaCard({super.key, required this.points, required this.onTap});

  /// Shared with [RelevantSevaCard] so one help-point type can never end up
  /// wearing two different icons in two places on the same screen.
  static const Map<int, IconData> _icons = {
    kStationMedical: Icons.medical_services,
    kStationWater: Icons.water_drop,
    kStationFood: Icons.restaurant,
    kStationLostChildDesk: Icons.child_care,
    kStationPolice: Icons.local_police,
    kStationToilet: Icons.wc,
    kStationNightHalt: Icons.bedtime,
    kStationCharging: Icons.charging_station,
    kStationFirstAid: Icons.health_and_safety,
    kStationOther: Icons.info,
  };

  static IconData iconFor(int helpType) =>
      _icons[helpType] ?? Icons.help_outline;

  static Color _statusColor(HelpPointRecord p) =>
      p.isLimited ? AppColors.warning : AppColors.relayed;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    if (points.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(Icons.volunteer_activism_outlined, size: 20, color: muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                t.listeningForSeva,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          for (final point in points)
            ListTile(
              onTap: () => onTap(point),
              leading: CircleAvatar(
                radius: 20,
                backgroundColor: _statusColor(point).withValues(alpha: 0.12),
                child: Icon(
                  _icons[point.helpType] ?? Icons.help_outline,
                  color: _statusColor(point),
                ),
              ),
              title: Text(
                t.station(point.helpType),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t.helpStatus(point.status)} · ${t.ageLabel(point.receivedAt)}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  // Where it is, or the honest reason there is no distance.
                  // See HelpPointRecord.whereLabel — never fabricated.
                  Text(
                    t.whereLabel(
                      hasLocation: point.hasLocation,
                      distanceMetres: point.distanceMetres,
                      bearingDegrees: point.bearingDegrees,
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: point.distanceLabel == null
                          ? muted
                          : AppColors.relayed,
                      fontWeight: point.distanceLabel == null
                          ? null
                          : FontWeight.w700,
                    ),
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
            ),
        ],
      ),
    );
  }
}

/// What happened to the alert you sent.
///
/// Before ACK packets existed, pressing SOS ended in a confirmation screen
/// and then silence — the app could tell you your alert had gone out, and
/// nothing whatsoever about whether it reached a human. This card is the
/// other end of that: it turns "sent" into "Sunita is responding", which is
/// the difference between a broadcast and being answered.
class MyAlertCard extends StatelessWidget {
  final AlertRecord alert;
  final String Function(String) nameFor;

  /// "Volunteer" / "Dindi Lead" / "Warkari" for a responder's Mesh ID — see
  /// responderRoleLabel() in models.dart. Optional so callers that don't
  /// have a MeshService handy (none currently, but nothing here should
  /// require one) still compile; falls back to no role suffix.
  final String Function(String)? roleFor;

  const MyAlertCard({
    super.key,
    required this.alert,
    required this.nameFor,
    this.roleFor,
  });

  @override
  Widget build(BuildContext context) {
    final answered = alert.isClaimed || alert.isResolved;
    final color = alert.isResolved
        ? AppColors.relayed
        : (answered ? AppColors.relayed : AppColors.warning);

    final String headline;
    final String detail;
    if (alert.isResolved) {
      headline = t.statusClosed;
      detail = t.alertFinished(t.ageLabel(alert.receivedAt));
    } else if (alert.isClaimed) {
      headline = t.helpIsComing;
      final role = roleFor?.call(alert.claimedBy!);
      final who = role == null
          ? nameFor(alert.claimedBy!)
          : '${nameFor(alert.claimedBy!)} · $role';
      detail = role == null
          ? t.respondingToYours(who)
          : '$who · $role ${t.responderVerbFor(role)}.';
    } else {
      headline = t.yourAlertIsOut;
      detail = t.alertOutDetail(t.ageLabel(alert.receivedAt));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            alert.isResolved
                ? Icons.check_circle
                : (answered ? Icons.directions_run : Icons.podcasts),
            color: color,
            size: 26,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
                // Honest about what the mesh can actually confirm: the
                // broadcast went out and every phone in range relays it —
                // that's provable. Whether the Dindi Lead's phone is even
                // switched on is not, so this says "propagated", never
                // "received". See the note on kResolvePacketType and
                // kAckPacketType for why nothing in this protocol can prove
                // delivery to a specific phone.
                if (alert.isSos && !answered) ...[
                  const SizedBox(height: 10),
                  const _PropagationChecklist(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "✓ Alert propagated to your Dindi · ✓ Alert propagated to nearby
/// volunteers" — the two lines requirement 6 of the Wari Emergency
/// Response Network asks for. Both are true the instant the alert is
/// broadcast: an SOS is never tiered down (see the note in
/// MeshService._handleReceivedPacket), so every phone in range — Dindi Lead
/// or not, Volunteer or not — receives and relays it. What this checklist
/// deliberately does NOT say is "received": there is no acknowledgement
/// mechanism for that short of an actual ACK, which is what the "Help is
/// coming" state above is for.
class _PropagationChecklist extends StatelessWidget {
  const _PropagationChecklist();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CheckLine(text: t.sosPropagatedDindi, muted: muted),
        _CheckLine(text: t.sosPropagatedVolunteers, muted: muted),
      ],
    );
  }
}

class _CheckLine extends StatelessWidget {
  final String text;
  final Color muted;
  const _CheckLine({required this.text, required this.muted});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          const Icon(Icons.check, size: 14, color: AppColors.relayed),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

/// Advisories from volunteers, on the screen a pilgrim actually looks at.
///
/// Advisories have always reached every phone in range and always rendered
/// inside the chat thread (see _AdvisoryCard in chat_screen.dart) — but a
/// warkari does not live in the chat thread. The volunteer side has a whole
/// tab for broadcasting these; the receiving side had nothing but a badge on
/// a tab most people never open, so a route change could be sitting unread
/// on a hundred phones. This is the other half of that feature.
///
/// Newest first, capped, and tapping anything opens the full thread — this
/// is a notice board, not a second inbox.
class AdvisoriesCard extends StatelessWidget {
  final List<MeshTextMessage> advisories;
  final VoidCallback onOpenAll;

  const AdvisoriesCard({
    super.key,
    required this.advisories,
    required this.onOpenAll,
  });

  @override
  Widget build(BuildContext context) {
    if (advisories.isEmpty) return const SizedBox.shrink();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    // Two at most. A third advisory pushes the SOS button off the screen,
    // and the thread is one tap away for the rest.
    final shown = advisories.take(2).toList();
    final more = advisories.length - shown.length;

    return Material(
      color: AppColors.warning.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onOpenAll,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.campaign,
                    color: AppColors.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      advisories.length == 1
                          ? t.advisory
                          : t.advisoryCount(advisories.length),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.warning),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                t.advisoriesFromVolunteers,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: muted),
              ),
              const SizedBox(height: 10),
              for (final advisory in shown)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        advisory.body,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${advisory.displayName} · ${TimeOfDay.fromDateTime(advisory.createdAt).format(context)}',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
              if (more > 0) ...[
                const SizedBox(height: 8),
                Text(
                  t.moreTapToRead(more),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: AppColors.warning,
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

/// The SOS → Seva bridge: help points worth walking to for the emergency
/// you just reported.
///
/// Renders nothing at all when nothing relevant has been heard, and that is
/// the important behaviour rather than a missing empty state. This card is
/// shown to somebody who has just pressed SOS; telling them "no water point
/// nearby" when the truth is "no water point has announced itself within
/// Bluetooth range of this phone" would be a claim the mesh cannot make. The
/// absence of a card says exactly as much as the mesh actually knows.
///
/// Never shows a distance — see the note on HelpPointsCard for why "in
/// range" is the only honest proximity signal a presence-discovered help
/// point has.
class RelevantSevaCard extends StatelessWidget {
  final int reason;
  final List<HelpPointRecord> seva;
  final ValueChanged<HelpPointRecord> onTap;

  const RelevantSevaCard({
    super.key,
    required this.reason,
    required this.seva,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (seva.isEmpty) return const SizedBox.shrink();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    // Cap the list: someone mid-emergency needs the nearest couple of
    // options, not an inventory.
    final shown = seva.take(3).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.relayed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.relayed.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.volunteer_activism,
                color: AppColors.relayed,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shown.length == 1
                      ? t.stationNearby(t.station(shown.first.helpType))
                      : t.nearbySeva,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.relayed,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            t.sevaDiscoveredThroughMesh,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 10),
          for (final point in shown)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onTap(point),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          NearbySevaCard.iconFor(point.helpType),
                          size: 20,
                          color: AppColors.relayed,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.station(point.helpType),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${t.helpStatus(point.status)} · ${t.ageLabel(point.receivedAt)}',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(color: muted),
                              ),
                              Text(
                                t.whereLabel(
                                  hasLocation: point.hasLocation,
                                  distanceMetres: point.distanceMetres,
                                  bearingDegrees: point.bearingDegrees,
                                ),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: point.distanceLabel == null
                                          ? muted
                                          : AppColors.relayed,
                                      fontWeight: point.distanceLabel == null
                                          ? null
                                          : FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          t.view,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: AppColors.relayed,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: AppColors.relayed,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "DINDI EMERGENCIES" — a Dindi Lead's coordination queue. Shown only when
/// MeshService.amDindiLead is true and there's something in it; see
/// MeshService.dindiEmergencies for the filter (open SOS from this phone's
/// own Dindi, reusing the same AlertRecord/ACK/RESOLVE machinery the
/// volunteer response queue runs on — nothing here is a new packet or a
/// new state).
class DindiEmergenciesSection extends StatelessWidget {
  final List<AlertRecord> emergencies;
  final MeshService mesh;
  final String dindiName;
  final VoidCallback onCoordinate;

  const DindiEmergenciesSection({
    super.key,
    required this.emergencies,
    required this.mesh,
    required this.dindiName,
    required this.onCoordinate,
  });

  @override
  Widget build(BuildContext context) {
    if (emergencies.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: t.dindiEmergencies,
          trailing: StatusPill(
            text: mrNum(emergencies.length),
            color: AppColors.sos,
            icon: Icons.sos,
          ),
        ),
        for (final alert in emergencies) ...[
          DindiEmergencyCard(
            alert: alert,
            mesh: mesh,
            dindiName: dindiName,
            onCoordinate: onCoordinate,
          ),
          if (alert != emergencies.last) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// One SOS from the Lead's own Dindi. Deliberately a smaller, denser card
/// than AlertsScreen's AlertQueueCard (alerts_screen.dart) — this lives on
/// the Home screen among other cards, not a dedicated full-screen queue —
/// but RESPOND drives the exact same mesh.claimAlert() call, so first-claim-
/// wins and the "Taken"/role-label behaviour are identical either way.
class DindiEmergencyCard extends StatelessWidget {
  final AlertRecord alert;
  final MeshService mesh;
  final String dindiName;
  final VoidCallback onCoordinate;

  const DindiEmergencyCard({
    super.key,
    required this.alert,
    required this.mesh,
    required this.dindiName,
    required this.onCoordinate,
  });

  /// Three live states, in the order they actually happen. "Searching" is
  /// the missing-person wording for the same unclaimed state an SOS calls
  /// "Unattended" — a Lead reading it should see the word that matches what
  /// is going on, not a generic status.
  String get _statusText {
    if (alert.isSpotted) return t.statusSpotted;
    if (alert.isClaimed) return t.statusTaken;
    return alert.isSos ? t.statusUnattended : t.statusSearching;
  }

  Color get _statusColor {
    if (alert.isSpotted) return AppColors.warning;
    if (alert.isClaimed) return AppColors.warning;
    return AppColors.sos;
  }

  IconData get _statusIcon {
    if (alert.isSpotted) return Icons.visibility;
    if (alert.isClaimed) return Icons.directions_run;
    return Icons.priority_high;
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final claimed = alert.isClaimed;
    final who = alert.senderName ?? alert.senderLabel;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.sos.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.sos.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                alert.isSos ? Icons.sos : Icons.person_search,
                color: AppColors.sos,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  alert.isSos ? t.sosFromYourDindi : t.missingFromYourDindi,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              StatusPill(
                text: _statusText,
                color: _statusColor,
                icon: _statusIcon,
              ),
            ],
          ),
          // The reason, given its own line at full size — for a Lead
          // deciding whether to walk over or send someone, "Medical" versus
          // "Lost / Separated" is the entire decision.
          if (alert.reasonLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              '${alert.reasonEmoji}  ${t.sosReason(alert.reason)}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: AppColors.sos,
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (!alert.isSos && alert.lostSummary != null)
            _Field(label: t.lookingFor, value: alert.lostSummary!),
          _Field(label: t.member, value: who),
          _Field(label: t.dindi, value: dindiName),
          _Field(label: t.place, value: _locationText()),
          _Field(
            label: t.time,
            value: TimeOfDay.fromDateTime(alert.receivedAt).format(context),
          ),
          if (alert.isSpotted) SpottedLine(alert: alert, mesh: mesh),
          if (claimed) ...[
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final role = mesh.responderRoleLabelFor(alert.claimedBy!);
                final name = mesh.nameFor(alert.claimedBy!) ?? alert.claimedBy!;
                return Text(
                  '$name · $role ${t.responderVerbFor(role)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                    fontSize: 13,
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          // A missing-person case gets FOUND as its primary action rather
          // than RESPOND — the Lead's job on a search is to close it the
          // moment the person is back, and "found" is the one word everyone
          // on the mesh is waiting for.
          if (!alert.isSos) ...[
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.relayed,
                    ),
                    onPressed: () =>
                        mesh.resolveAlert(alert, reason: kResolveFound),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(t.found),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => mesh.reportSpotted(alert),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: Text(t.spotted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              if (!alert.isSos)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCoordinate,
                    icon: const Icon(Icons.forum_outlined, size: 18),
                    label: Text(t.coordinate),
                  ),
                )
              else if (!claimed)
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.sos,
                    ),
                    onPressed: () => mesh.claimAlert(alert),
                    icon: const Icon(Icons.pan_tool_alt, size: 18),
                    label: Text(t.respond),
                  ),
                )
              else if (!alert.claimedByMe(mesh.myMeshId))
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => mesh.claimAlert(alert),
                    icon: const Icon(Icons.group_add_outlined, size: 18),
                    label: Text(t.joinAnyway),
                  ),
                )
              else
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => mesh.resolveAlert(alert),
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(t.closeAlert),
                  ),
                ),
              // A missing-person case already offered COORDINATE as its own
              // full-width action above, alongside FOUND/SPOTTED — this
              // second one is the SOS layout's partner to RESPOND.
              if (alert.isSos) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCoordinate,
                    icon: const Icon(Icons.forum_outlined, size: 18),
                    label: Text(t.coordinate),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${t.relayedThrough(alert.hops)} · ${t.ageLabel(alert.receivedAt)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: muted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  /// Never fabricated — see the note on kLocationPacketType. Distance/
  /// direction only appear once a LocationPacket has actually arrived and
  /// this phone knows its own position; otherwise this says so plainly.
  String _locationText() {
    return t.whereLabel(
      hasLocation: alert.hasLocation,
      distanceMetres: alert.distanceMetres,
      bearingDegrees: alert.bearingDegrees,
    );
  }
}

/// "👀 Sunita reported seeing them · 4 min ago" — the live state of a
/// search between "nobody has seen them" and "found". Shared by the Dindi
/// Lead's card and the volunteer queue so a sighting reads identically to
/// everyone working the same case.
///
/// Attributed, never asserted: a SPOTTED packet is unauthenticated like
/// every other response packet (see kSpottedPacketType), so this says who
/// reported it rather than stating it as fact.
class SpottedLine extends StatelessWidget {
  final AlertRecord alert;
  final MeshService mesh;

  const SpottedLine({super.key, required this.alert, required this.mesh});

  @override
  Widget build(BuildContext context) {
    final by = alert.spottedBy;
    if (by == null) return const SizedBox.shrink();
    final who = by == mesh.myMeshId ? 'You' : (mesh.nameFor(by) ?? by);
    final at = alert.spottedAt;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.visibility, size: 18, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.spottedBy(
                      who,
                      at == null
                          ? null
                          : TimeOfDay.fromDateTime(at).format(context),
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.warning,
                      fontSize: 13,
                    ),
                  ),
                  // Never fabricated. A sighting with no position is still
                  // worth a great deal — it says the person is alive and on
                  // this stretch of route — and says exactly that.
                  Text(
                    alert.hasSpottedLocation
                        ? t.positionSentWithSighting
                        : t.noPositionWithSighting,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;
  const _Field({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the warkari's current Dindi (or an invite to set one) and its live
/// headcount (via presence beacons — see MeshService.dindiHeadcount).
///
/// Tapping the card behaves differently depending on state, on purpose:
///  - No Dindi yet → straight into Create/Join (dindi_picker.dart) —
///    nothing to manage yet.
///  - Already in a Dindi → opens a "manage" sheet (member list + Leave +
///    Join a different Dindi) instead of silently reopening Create/Join.
///    Changing Dindi is now a deliberate action from inside that sheet,
///    not an accidental side effect of tapping the card again.
class DindiCard extends StatelessWidget {
  final String groupOrId;
  final int headcount;
  final List<String> memberNames;
  final ValueChanged<String> onDindiChanged;

  /// The Dindi Lead toggle only makes sense for a warkari (see the note on
  /// UserProfile.isDindiLead) — [onDindiLeadChanged] being non-null is what
  /// shows it, so the volunteer dashboard's DindiCard (same widget, shared
  /// per the note at the top of this file) doesn't grow a control that
  /// means nothing there.
  final bool isDindiLead;
  final ValueChanged<bool>? onDindiLeadChanged;

  const DindiCard({
    super.key,
    required this.groupOrId,
    required this.headcount,
    required this.memberNames,
    required this.onDindiChanged,
    this.isDindiLead = false,
    this.onDindiLeadChanged,
  });

  bool get _hasDindi => groupOrId.isNotEmpty && groupOrId != '—';

  Future<void> _onTap(BuildContext context) async {
    if (!_hasDindi) {
      final name = await showDindiSheet(context, currentName: groupOrId);
      if (name != null) onDindiChanged(name);
      return;
    }
    await _showManageSheet(context);
  }

  Future<void> _showManageSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(sheetContext).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.relayed.withValues(alpha: 0.15),
                    child: const Icon(Icons.groups, color: AppColors.relayed),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          groupOrId,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Code ${dindiTagFor(groupOrId)} · $headcount nearby',
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                t.membersNearby,
                style: Theme.of(sheetContext).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              MemberTile(name: t.you, isYou: true),
              ...memberNames.map((name) => MemberTile(name: name)),
              if (memberNames.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'No one else from your Dindi is in range yet. Members appear here automatically when their phone is nearby.',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                ),
              if (onDindiLeadChanged != null) ...[
                const SizedBox(height: 16),
                // Closes the sheet on toggle rather than trying to reflect
                // the change live in place — the sheet's DindiCard fields
                // are a snapshot taken when it opened (this is a modal
                // route, not part of the normal rebuild tree), same reason
                // "Join a different Dindi" and "Leave Dindi" below both pop
                // before acting instead of trying to update in place.
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isDindiLead,
                  onChanged: (v) {
                    Navigator.of(sheetContext).pop();
                    onDindiLeadChanged!(v);
                  },
                  title: Text(
                    t.iAmDindiLead,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    t.iAmDindiLeadDetail,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.swap_horiz),
                label: Text(t.joinDifferentDindi),
                onPressed: () async {
                  Navigator.of(sheetContext).pop();
                  final name = await showDindiSheet(
                    context,
                    currentName: groupOrId,
                  );
                  if (name != null) onDindiChanged(name);
                },
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.sos),
                icon: const Icon(Icons.logout, size: 18),
                label: Text(t.leaveDindi),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  onDindiChanged('—');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Green (the "mesh is working" colour) when you're in a Dindi; a muted
    // neutral when you aren't yet, so an unset Dindi reads as an empty slot
    // to fill rather than as a live, healthy state.
    final color = _hasDindi ? AppColors.relayed : AppColors.neutral;

    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _onTap(context),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(
                  _hasDindi ? Icons.groups : Icons.group_add_outlined,
                  color: color,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hasDindi ? groupOrId : t.createOrJoinDindi,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _hasDindi
                          ? 'Code ${dindiTagFor(groupOrId)} · tap to see members'
                          : 'Walk together — your Dindi hears your SOS loudest',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (_hasDindi)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person, size: 15, color: color),
                      const SizedBox(width: 4),
                      Text(
                        '$headcount',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// One person in the Dindi member list. "You" is always first and marked,
/// so the headcount visibly adds up (you + everyone listed below).
class MemberTile extends StatelessWidget {
  final String name;
  final bool isYou;

  const MemberTile({super.key, required this.name, this.isYou = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.relayed.withValues(alpha: 0.12),
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: const TextStyle(
                color: AppColors.relayed,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          if (isYou) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('you', style: Theme.of(context).textTheme.labelSmall),
            ),
          ],
        ],
      ),
    );
  }
}

/// The slim mesh-connection strip at the top of the grid. Deliberately the
/// least visually heavy box on the screen — it's status, not an action.
class StatusBox extends StatelessWidget {
  final bool bluetoothOn;
  final bool scanningOk;

  const StatusBox({
    super.key,
    required this.bluetoothOn,
    required this.scanningOk,
  });

  @override
  Widget build(BuildContext context) {
    final color = scanningOk ? AppColors.relayed : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(
            scanningOk ? Icons.sensors : Icons.sensors_off,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              !bluetoothOn
                  ? t.bluetoothOff
                  : scanningOk
                  ? t.meshConnected
                  : t.meshNotConnected,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A square-ish action tile. Two of these sit side by side under the Dindi
/// box; [IntrinsicHeight] in the parent keeps them equal height even when
/// one subtitle wraps to a second line.
class ActionBox extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const ActionBox({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(icon, color: color, size: 26),
                  ),
                  const Spacer(),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
