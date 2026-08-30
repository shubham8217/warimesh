// WariMesh — the volunteer's home screen: their duty state.
//
// This used to be the warkari dashboard with mesh diagnostics bolted
// underneath, which is what it looks like when a role is a skin rather than
// a job. A volunteer does not open this app to send an SOS. They open it to
// find out whether anyone needs them, and to say what they are standing
// next to.
//
// So the screen is, top to bottom:
//   1. the queue     — how many people are waiting, unmissable
//   2. duty          — which help point this phone is announcing
//   3. the camp      — who else is here
//   4. relay health  — one line, with the detail a tap away in OpsScreen
//
// Sending an SOS and filing a missing-person report are still available, in
// the overflow menu. A volunteer can be in trouble too; it is just not what
// this screen is for.
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';
import 'activity_log_screen.dart';
import 'home_widgets.dart';
import 'ops_screen.dart';

class HomeScreen extends StatelessWidget {
  final MeshService mesh;
  final UserProfile volunteer;
  final VoidCallback onLogout;
  final VoidCallback onOpenSos;
  final VoidCallback onOpenMissing;
  final VoidCallback onOpenAlerts;
  final ValueChanged<String> onDindiChanged;
  final ValueChanged<int> onStationChanged;

  const HomeScreen({
    super.key,
    required this.mesh,
    required this.volunteer,
    required this.onLogout,
    required this.onOpenSos,
    required this.onOpenMissing,
    required this.onOpenAlerts,
    required this.onDindiChanged,
    required this.onStationChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scanningOk = mesh.scanning && mesh.bluetoothOn;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: Row(
            children: [
              const Icon(Icons.support_agent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  volunteer.name.split(' ').first,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'भाषा / Language',
              icon: const Icon(Icons.translate),
              onPressed: () => showLanguageSheet(context),
            ),
            IconButton(
              tooltip: 'Relay status',
              icon: const Icon(Icons.hub_outlined),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => OpsScreen(mesh: mesh))),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                switch (v) {
                  case 'sos':
                    onOpenSos();
                  case 'missing':
                    onOpenMissing();
                  case 'log':
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ActivityLogScreen(mesh: mesh),
                      ),
                    );
                  case 'logout':
                    onLogout();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(
                    '${volunteer.name} · ${mesh.myMeshId}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'sos',
                  child: Row(
                    children: [
                      Icon(Icons.sos, size: 18, color: AppColors.sos),
                      SizedBox(width: 10),
                      Text('Send an SOS'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'missing',
                  child: Row(
                    children: [
                      Icon(Icons.person_add_alt, size: 18),
                      SizedBox(width: 10),
                      Text('Report someone missing'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'log',
                  child: Row(
                    children: [
                      Icon(Icons.history, size: 18),
                      SizedBox(width: 10),
                      Text('Activity log'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 18),
                      SizedBox(width: 10),
                      Text('Sign out'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              QueueSummary(mesh: mesh, onOpenAlerts: onOpenAlerts),
              const SizedBox(height: 12),
              DutyCard(
                station: mesh.myStation,
                onStationChanged: onStationChanged,
              ),
              const SizedBox(height: 12),
              DindiCard(
                groupOrId: volunteer.groupOrId,
                headcount: mesh.dindiHeadcount,
                memberNames: mesh.dindiMemberNames,
                onDindiChanged: onDindiChanged,
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => OpsScreen(mesh: mesh)),
                ),
                child: StatusBox(
                  bluetoothOn: mesh.bluetoothOn,
                  scanningOk: scanningOk,
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

/// The top of the volunteer's home: how many people are waiting on someone.
///
/// It is the first thing on the screen and the only thing that changes size,
/// because the difference between "nothing waiting" and "two people need
/// help" is the entire content of a volunteer's next thirty seconds.
class QueueSummary extends StatelessWidget {
  final MeshService mesh;
  final VoidCallback onOpenAlerts;

  const QueueSummary({
    super.key,
    required this.mesh,
    required this.onOpenAlerts,
  });

  @override
  Widget build(BuildContext context) {
    final queue = mesh.triagedAlerts.where((a) => !a.mine).toList();
    final unclaimed = queue.where((a) => a.isOpen).length;
    final claimed = queue.where((a) => a.isClaimed).length;
    final quiet = unclaimed == 0 && claimed == 0;
    final color = unclaimed > 0
        ? AppColors.sos
        : (claimed > 0 ? AppColors.warning : AppColors.relayed);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onOpenAlerts,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: quiet ? 0.08 : 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(
              quiet ? Icons.check_circle_outline : Icons.notifications_active,
              color: color,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quiet
                        ? 'Nobody waiting'
                        : '$unclaimed ${unclaimed == 1 ? 'person needs' : 'people need'} help',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    quiet
                        ? 'Listening. Anything that arrives shows up here.'
                        : claimed > 0
                        ? '$claimed already being handled'
                        : 'Nobody has responded yet',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// Going on duty at a help point.
///
/// This is the one switch on a volunteer's phone that changes what pilgrims
/// around them can see. Off by default and off after every sign-in, because
/// a phone claiming to be a medical point when nobody is staffing one sends
/// someone in the wrong direction during the minutes that matter — worse
/// than claiming nothing at all.
class DutyCard extends StatelessWidget {
  final int station;
  final ValueChanged<int> onStationChanged;

  const DutyCard({
    super.key,
    required this.station,
    required this.onStationChanged,
  });

  static const Map<int, IconData> _icons = {
    kStationNone: Icons.person_outline,
    kStationMedical: Icons.medical_services_outlined,
    kStationWater: Icons.water_drop_outlined,
    kStationFood: Icons.restaurant_outlined,
    kStationLostChildDesk: Icons.child_care_outlined,
    kStationPolice: Icons.local_police_outlined,
    kStationToilet: Icons.wc_outlined,
    kStationNightHalt: Icons.bedtime_outlined,
    kStationCharging: Icons.charging_station_outlined,
    kStationFirstAid: Icons.health_and_safety_outlined,
    kStationOther: Icons.info_outline,
  };

  /// One tap, one question, one button — see the note at the top of this
  /// file's spec ("Wari volunteers may be walking and using phones in
  /// crowded environments") for why this is a single confirm, not a form.
  Future<void> _confirmAndAnnounce(BuildContext context, int newStation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(_icons[newStation], color: AppColors.relayed, size: 32),
        title: Text(t.announceQuestion(t.station(newStation))),
        // Says plainly, at the moment of choosing, that the position goes
        // out — this is the one place a volunteer decides to publish
        // where they are standing.
        content: Text(t.announceConfirmBody(t.station(newStation))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.announce),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    onStationChanged(newStation);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.helpPointNowVisible(t.station(newStation)))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final onDuty = station != kStationNone;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final color = onDuty ? AppColors.relayed : muted;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(
                    _icons[station] ?? Icons.person_outline,
                    color: color,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        onDuty ? t.station(station) : t.notAtHelpPoint,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        onDuty ? t.pilgrimsCanSeeHelp : t.tapToAnnounce,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                if (onDuty)
                  TextButton(
                    onPressed: () {
                      onStationChanged(kStationNone);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(t.helpPointClosed)),
                      );
                    },
                    child: Text(t.offDuty),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in kStationTypes.where((s) => s != kStationNone))
                  ChoiceChip(
                    avatar: Icon(_icons[s], size: 17),
                    label: Text(t.station(s)),
                    selected: station == s,
                    onSelected: (sel) {
                      if (!sel) {
                        onStationChanged(kStationNone);
                        return;
                      }
                      _confirmAndAnnounce(context, s);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
