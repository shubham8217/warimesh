// WariMesh — the warkari's (pilgrim's) home tab: a trimmed-down dashboard
// next to the volunteer one (home_screen.dart). No mesh diagnostics,
// background-service switch, or activity log here — just "am I connected"
// at a glance, the two things a pilgrim actually needs (SOS, Missing), and
// who's currently reported missing nearby.
import 'package:flutter/material.dart';

import '../database_service.dart';
import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';
import 'home_widgets.dart';

class WarkariHomeScreen extends StatefulWidget {
  final MeshService mesh;
  final UserProfile warkari;
  final VoidCallback onLogout;
  final VoidCallback onOpenSos;
  final VoidCallback onOpenMissing;
  final ValueChanged<String> onDindiChanged;

  const WarkariHomeScreen({
    super.key,
    required this.mesh,
    required this.warkari,
    required this.onLogout,
    required this.onOpenSos,
    required this.onOpenMissing,
    required this.onDindiChanged,
  });

  @override
  State<WarkariHomeScreen> createState() => _WarkariHomeScreenState();
}

class _WarkariHomeScreenState extends State<WarkariHomeScreen> {
  List<LostReport> _reports = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final reports = await LostReportsDb.all();
      if (mounted) setState(() => _reports = reports);
    } catch (_) {
      // Local DB unavailable — leave the list empty rather than crash.
    }
  }

  @override
  Widget build(BuildContext context) {
    final mesh = widget.mesh;
    final activeMissing = _reports.where((r) => !r.found).length;
    final scanningOk = mesh.scanning && mesh.bluetoothOn;
    final helpPoints = mesh.helpPointsInRange;

    // The most recent alert this phone sent that hasn't been closed — or,
    // if it has, only while it's fresh enough to still be the thing on this
    // person's mind. An SOS from three hours ago is history, not status.
    final myAlerts = mesh.alerts.where((a) => a.mine).toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    final AlertRecord? myAlert = myAlerts.isEmpty
        ? null
        : (myAlerts.first.isResolved &&
                DateTime.now().difference(myAlerts.first.receivedAt).inMinutes > 30
            ? null
            : myAlerts.first);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: Row(
            children: [
              const Icon(Icons.directions_walk),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Namaskar, ${widget.warkari.name.split(' ').first}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Account',
              icon: const Icon(Icons.person_outline),
              onSelected: (v) {
                if (v == 'logout') widget.onLogout();
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(widget.warkari.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'logout',
                  child: Row(children: [Icon(Icons.logout, size: 18), SizedBox(width: 10), Text('Sign out')]),
                ),
              ],
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Everything on this screen is a box in one grid: a slim
              // status strip, the Dindi box (full width — it carries the
              // headcount and member list), then the two actions side by
              // side. No section headers: with only three tiles the labels
              // were adding a layer of hierarchy the screen doesn't need.
              // Your own alert first when you have one in flight. Someone
              // who has just pressed SOS is looking at this screen for one
              // reason: to find out whether anything happened.
              if (myAlert != null) ...[
                MyAlertCard(
                  alert: myAlert,
                  nameFor: (id) => mesh.nameFor(id) ?? id,
                ),
                const SizedBox(height: 12),
              ],
              StatusBox(bluetoothOn: mesh.bluetoothOn, scanningOk: scanningOk),
              if (helpPoints.isNotEmpty) ...[
                const SizedBox(height: 12),
                HelpPointsCard(points: helpPoints),
              ],
              const SizedBox(height: 12),
              DindiCard(
                groupOrId: widget.warkari.groupOrId,
                headcount: mesh.dindiHeadcount,
                memberNames: mesh.dindiMemberNames,
                onDindiChanged: widget.onDindiChanged,
              ),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ActionBox(
                        color: AppColors.sos,
                        icon: Icons.sos,
                        title: 'Send SOS',
                        subtitle: 'Alert nearby phones',
                        onTap: widget.onOpenSos,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ActionBox(
                        color: AppColors.lostPerson,
                        icon: Icons.person_search,
                        title: 'Missing',
                        subtitle: activeMissing == 0
                            ? 'Report or search'
                            : '$activeMissing active report${activeMissing == 1 ? '' : 's'}',
                        badge: activeMissing == 0 ? null : '$activeMissing',
                        onTap: widget.onOpenMissing,
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
