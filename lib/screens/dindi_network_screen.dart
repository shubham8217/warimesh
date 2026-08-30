// WariMesh — the volunteer's view of the Dindis around them.
//
// This is the screen that makes the point WariMesh exists to make: without
// any network at all, a volunteer standing at a camp can see which Dindis
// are around them, who leads them, and which of them are in trouble.
//
// Every number on it is counted from data this phone actually heard, and the
// wording is chosen so nobody can read more into it than that:
//
//  - A Dindi appears because one of its phones is within Bluetooth range.
//    Presence beacons are single-hop and never relayed (see
//    kPresencePacketType), so this is "Dindis I can hear", never "Dindis on
//    the Wari". The caption says so.
//  - Member counts are WariMesh participants audible right now. There is no
//    registered-membership data anywhere in this app, so no total is shown
//    beside them — an invented "184" next to a real "3" would make the real
//    number look like the wrong one.
//  - Dindi NAMES do not travel. The wire carries a two-character code (see
//    dindiTagFor), so a Dindi shows its name only when this phone already
//    knows it, and its code otherwise.
//  - Mukkaam has no source in the protocol. Rather than invent a route
//    model, the screen shows night-halt Seva when some has been announced
//    nearby, and says plainly that nothing else is available.
//
// See DindiSummary and WariNetworkStats in mesh_service.dart, which do the
// counting and carry the same warnings.
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../mesh_service.dart';
import '../theme.dart';
import '../widgets.dart';

/// How recently a Dindi Lead's beacon must have been heard to call them
/// "nearby". Matches the presence window the rest of the app uses.
const Duration _kLeadNearby = kPresenceExpiry;

class DindiNetworkScreen extends StatelessWidget {
  final MeshService mesh;
  final VoidCallback onOpenAlerts;

  const DindiNetworkScreen({
    super.key,
    required this.mesh,
    required this.onOpenAlerts,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: mesh,
      builder: (context, _) {
        final dindis = mesh.knownDindis;
        return Scaffold(
          appBar: AppBar(title: Text(t.dindisHeading)),
          body: dindis.isEmpty
              ? _EmptyDindis()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: dindis.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    if (i == 0) return _SingleHopNote();
                    return DindiCardSummary(
                      dindi: dindis[i - 1],
                      mesh: mesh,
                      onOpenAlerts: onOpenAlerts,
                    );
                  },
                ),
        );
      },
    );
  }
}

/// Said once at the top of the list rather than repeated on every card: the
/// numbers below are what this phone can hear.
class _SingleHopNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 16, color: muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            t.participantsSingleHopNote,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}

class _EmptyDindis extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.groups_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              t.noDindisHeard,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              t.noDindisHeardDetail,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// One Dindi in the list. Leads with trouble when there is any, because
/// that is the only reason a volunteer is reading this screen quickly.
class DindiCardSummary extends StatelessWidget {
  final DindiSummary dindi;
  final MeshService mesh;
  final VoidCallback onOpenAlerts;

  const DindiCardSummary({
    super.key,
    required this.dindi,
    required this.mesh,
    required this.onOpenAlerts,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final accent = dindi.hasEmergency ? AppColors.sos : AppColors.relayed;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DindiDetailScreen(
              tag: dindi.tag,
              mesh: mesh,
              onOpenAlerts: onOpenAlerts,
            ),
          ),
        ),
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
                    child: Icon(Icons.groups, color: accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: DindiTitle(dindi: dindi)),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              _Line(
                icon: Icons.person_outline,
                label: t.dindiLeads,
                value: dindi.leadName ?? t.unavailable,
                trailing: dindi.hasLead
                    ? (dindi.leadIsNearby(_kLeadNearby)
                          ? t.leadNearby
                          : '${t.leadLastSeen}: ${t.ageLabel(dindi.leadLastHeard!)}')
                    : null,
              ),
              _Line(
                icon: Icons.people_outline,
                label: t.visibleInWariMesh,
                value: mrNum(dindi.visibleMembers),
              ),
              _Line(
                icon: Icons.schedule,
                label: t.lastUpdate,
                value: t.ageLabel(dindi.lastHeard),
              ),
              const SizedBox(height: 10),
              if (dindi.hasEmergency)
                EmergencyStrip(dindi: dindi, onTap: onOpenAlerts)
              else
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: AppColors.relayed,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.noEmergencies,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Dindi's name when this phone knows it, its code otherwise — with the
/// code always shown, because that is the identity that actually travels.
class DindiTitle extends StatelessWidget {
  final DindiSummary dindi;
  const DindiTitle({super.key, required this.dindi});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final named = dindi.name != null && dindi.name!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          named ? dindi.name! : '${t.dindisHeading} ${dindi.tag}',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        Text(
          '${t.dindiCode} ${dindi.tag}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

class EmergencyStrip extends StatelessWidget {
  final DindiSummary dindi;
  final VoidCallback onTap;

  const EmergencyStrip({super.key, required this.dindi, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.sos.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.sos, size: 18, color: AppColors.sos),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  [
                    if (dindi.activeSos > 0)
                      '${t.activeSos}: ${mrNum(dindi.activeSos)}',
                    if (dindi.activeMissing > 0)
                      '${t.missingWarkaris}: ${mrNum(dindi.activeMissing)}',
                  ].join('  ·  '),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.sos,
                    fontSize: 13,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.sos),
            ],
          ),
        ),
      ),
    );
  }
}

/// Everything this phone knows about one Dindi.
///
/// Rebuilt from [MeshService.dindiByTag] on every mesh change rather than
/// captured once, so a Dindi that goes out of range visibly stops being
/// current instead of freezing at its last good values.
class DindiDetailScreen extends StatelessWidget {
  final String tag;
  final MeshService mesh;
  final VoidCallback onOpenAlerts;

  const DindiDetailScreen({
    super.key,
    required this.tag,
    required this.mesh,
    required this.onOpenAlerts,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: mesh,
      builder: (context, _) {
        final dindi = mesh.dindiByTag(tag);
        final muted = Theme.of(context).colorScheme.onSurfaceVariant;

        if (dindi == null) {
          // The Dindi has gone out of range while this screen was open.
          // Said plainly rather than leaving stale numbers on screen.
          return Scaffold(
            appBar: AppBar(title: Text('${t.dindisHeading} $tag')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  t.noDindisHeard,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
            ),
          );
        }

        final mukkaam = mesh.mukkaamPoints;
        final seva = mesh.activeHelpPoints;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              dindi.name?.isNotEmpty == true
                  ? dindi.name!
                  : '${t.dindisHeading} ${dindi.tag}',
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              if (dindi.name == null) ...[
                _Note(text: t.dindiNameUnknown),
                const SizedBox(height: 12),
              ],

              // People first: who leads this Dindi, and how much of it this
              // phone can actually hear.
              _Section(
                title: t.dindiLeads,
                footnote: t.visibleInWariMeshCaption,
                children: [
                  _Line(
                    icon: Icons.person,
                    label: t.dindiLeads,
                    value: dindi.leadName ?? t.unavailable,
                    trailing: dindi.hasLead
                        ? (dindi.leadIsNearby(_kLeadNearby)
                              ? t.leadNearby
                              : '${t.leadLastSeen}: ${t.ageLabel(dindi.leadLastHeard!)}')
                        : null,
                  ),
                  _Line(
                    icon: Icons.people,
                    label: t.visibleInWariMesh,
                    value: mrNum(dindi.visibleMembers),
                  ),
                  _Line(
                    icon: Icons.volunteer_activism_outlined,
                    label: t.volunteers,
                    value: mrNum(dindi.visibleVolunteers),
                  ),
                  _Line(
                    icon: Icons.schedule,
                    label: t.lastUpdate,
                    value: t.ageLabel(dindi.lastHeard),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Emergencies, straight from the durable alert queue.
              _Section(
                title: t.activeSos,
                children: [
                  _Line(
                    icon: Icons.sos,
                    label: t.activeSos,
                    value: mrNum(dindi.activeSos),
                  ),
                  _Line(
                    icon: Icons.person_search,
                    label: t.missingWarkaris,
                    value: mrNum(dindi.activeMissing),
                  ),
                  if (dindi.hasEmergency) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.sos,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          onOpenAlerts();
                        },
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(t.viewActiveIncidents),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              // Location. Almost always unavailable, and that is correct —
              // presence carries no position, so the only Dindi location
              // that exists comes from a located alert somebody sent.
              _Section(
                title: t.lastKnownLocation,
                children: [
                  _Line(
                    icon: dindi.hasLocation
                        ? Icons.place
                        : Icons.location_off_outlined,
                    label: t.lastKnownLocation,
                    value: dindi.hasLocation
                        ? '${dindi.latitude!.toStringAsFixed(5)}, ${dindi.longitude!.toStringAsFixed(5)}'
                        : t.unavailable,
                    trailing: dindi.locationAt == null
                        ? null
                        : '${t.lastUpdate}: ${t.ageLabel(dindi.locationAt!)}',
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Mukkaam: night-halt Seva heard nearby, or an honest note
              // that the protocol carries no halt information at all.
              _Section(
                title: t.mukkaam,
                children: mukkaam.isEmpty
                    ? [_Note(text: t.mukkaamNoSource)]
                    : [
                        for (final m in mukkaam)
                          _Line(
                            icon: Icons.bedtime,
                            label: t.station(m.helpType),
                            value: t.helpStatus(m.status),
                            trailing: t.ageLabel(m.receivedAt),
                          ),
                      ],
              ),
              const SizedBox(height: 12),

              // Seva belongs to the network, not to this Dindi — the
              // heading says "nearby", never "this Dindi's".
              _Section(
                title: t.nearbySevaShort,
                children: seva.isEmpty
                    ? [_Note(text: t.unavailable)]
                    : [
                        for (final h in seva.take(6))
                          _Line(
                            icon: Icons.volunteer_activism,
                            label: t.station(h.helpType),
                            value: t.helpStatus(h.status),
                            trailing: t.ageLabel(h.receivedAt),
                          ),
                      ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final String? footnote;

  const _Section({required this.title, this.footnote, required this.children});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...children,
            if (footnote != null) ...[
              const SizedBox(height: 10),
              Text(
                footnote!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: muted, fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? trailing;

  const _Line({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: muted),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note({required this.text});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 16, color: muted),
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

/// The volunteer home screen's network overview: the whole local mesh in
/// one glance, with every number counted from what this phone can hear.
class WariNetworkCard extends StatelessWidget {
  final MeshService mesh;
  final VoidCallback onOpenDindis;

  const WariNetworkCard({
    super.key,
    required this.mesh,
    required this.onOpenDindis,
  });

  @override
  Widget build(BuildContext context) {
    final stats = mesh.wariNetwork;
    final live = mesh.scanning && mesh.bluetoothOn;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final color = live ? AppColors.relayed : AppColors.sos;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(live ? Icons.hub : Icons.link_off, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t.wariNetwork,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              StatusPill(
                text: live ? t.networkActive : t.networkDown,
                color: color,
                icon: live ? Icons.sensors : Icons.sensors_off,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Stat(
                icon: Icons.groups,
                label: t.dindisHeading,
                value: stats.dindis,
              ),
              _Stat(
                icon: Icons.people,
                label: t.participants,
                value: stats.participants,
              ),
              _Stat(
                icon: Icons.person,
                label: t.dindiLeads,
                value: stats.leads,
              ),
              _Stat(
                icon: Icons.volunteer_activism_outlined,
                label: t.volunteers,
                value: stats.volunteers,
              ),
              _Stat(
                icon: Icons.sos,
                label: t.activeSos,
                value: stats.activeSos,
                alert: stats.activeSos > 0,
              ),
              _Stat(
                icon: Icons.person_search,
                label: t.missingWarkaris,
                value: stats.activeMissing,
                alert: stats.activeMissing > 0,
              ),
              _Stat(
                icon: Icons.local_hospital_outlined,
                label: t.sevaPoints,
                value: stats.sevaPoints,
              ),
              _Stat(
                icon: Icons.bedtime_outlined,
                label: t.mukkaam,
                value: stats.mukkaamPoints,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The caption that keeps every number above honest.
          Text(
            t.participantsSingleHopNote,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: muted, fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: onOpenDindis,
              icon: const Icon(Icons.groups_outlined, size: 18),
              label: Text(t.viewDindis),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final bool alert;

  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = alert ? AppColors.sos : scheme.onSurface;
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mrNum(value),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11.5,
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
