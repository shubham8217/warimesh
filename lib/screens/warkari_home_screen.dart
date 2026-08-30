// WariMesh — the warkari's (pilgrim's) home tab: a trimmed-down dashboard
// next to the volunteer one (home_screen.dart). No mesh diagnostics,
// background-service switch, or activity log here — just "am I connected"
// at a glance, the two things a pilgrim actually needs (SOS, Missing), and
// who's currently reported missing nearby.
import 'package:flutter/material.dart';

import '../database_service.dart';
import '../l10n/app_strings.dart';
import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'help_point_detail_screen.dart';
import 'home_widgets.dart';

class WarkariHomeScreen extends StatefulWidget {
  final MeshService mesh;
  final UserProfile warkari;
  final VoidCallback onLogout;
  final VoidCallback onOpenSos;
  final VoidCallback onOpenMissing;
  final VoidCallback onOpenChat;
  final ValueChanged<String> onDindiChanged;
  final ValueChanged<bool> onDindiLeadChanged;

  const WarkariHomeScreen({
    super.key,
    required this.mesh,
    required this.warkari,
    required this.onLogout,
    required this.onOpenSos,
    required this.onOpenMissing,
    required this.onOpenChat,
    required this.onDindiChanged,
    required this.onDindiLeadChanged,
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
    final nearbySeva = mesh.activeHelpPoints;

    // The most recent alert this phone sent that hasn't been closed — or,
    // if it has, only while it's fresh enough to still be the thing on this
    // person's mind. An SOS from three hours ago is history, not status.
    final myAlerts = mesh.alerts.where((a) => a.mine).toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    final AlertRecord? myAlert = myAlerts.isEmpty
        ? null
        : (myAlerts.first.isResolved &&
                  DateTime.now()
                          .difference(myAlerts.first.receivedAt)
                          .inMinutes >
                      30
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
                  '${t.greeting}, ${widget.warkari.name.split(' ').first}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            // One tap, always in the same place — the overflow menu was
            // the wrong home for the one setting somebody needs when they
            // cannot read the menu.
            IconButton(
              tooltip: 'भाषा / Language',
              icon: const Icon(Icons.translate),
              onPressed: () => showLanguageSheet(context),
            ),
            PopupMenuButton<String>(
              tooltip: t.account,
              icon: const Icon(Icons.person_outline),
              onSelected: (v) {
                if (v == 'logout') widget.onLogout();
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(
                    widget.warkari.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'logout',
                  child: Row(
                    children: [
                      const Icon(Icons.logout, size: 18),
                      const SizedBox(width: 10),
                      Text(t.signOut),
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
                  roleFor: mesh.responderRoleLabelFor,
                ),
                const SizedBox(height: 12),
                // Seva worth walking to for the emergency you just reported.
                // Renders nothing when nothing relevant has been heard —
                // see RelevantSevaCard for why silence is the honest answer.
                if (!myAlert.isResolved) ...[
                  RelevantSevaCard(
                    reason: myAlert.reason,
                    seva: mesh.sevaForReason(myAlert.reason),
                    onTap: (point) => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            HelpPointDetailScreen(mesh: mesh, point: point),
                      ),
                    ),
                  ),
                  if (mesh.sevaForReason(myAlert.reason).isNotEmpty)
                    const SizedBox(height: 12),
                ],
              ],
              // Only ever populated when this phone has declared itself the
              // Dindi Lead (see MeshService.amDindiLead) — an ordinary
              // Warkari's dindiEmergencies list is always empty, so this
              // section simply never renders for them. It still shows up
              // even without myAlert above: a Lead coordinating someone
              // else's SOS has no alert of their own in flight.
              if (mesh.amDindiLead) ...[
                DindiEmergenciesSection(
                  emergencies: mesh.dindiEmergencies,
                  mesh: mesh,
                  dindiName: widget.warkari.groupOrId,
                  onCoordinate: widget.onOpenChat,
                ),
                if (mesh.dindiEmergencies.isNotEmpty)
                  const SizedBox(height: 12),
              ],
              // Above Nearby Seva and the Dindi card: an advisory is
              // time-critical ("route closed ahead") in a way a help point
              // listing is not, and it is the one thing on this screen
              // somebody else decided you needed to know.
              if (mesh.recentAdvisories.isNotEmpty) ...[
                AdvisoriesCard(
                  advisories: mesh.recentAdvisories,
                  onOpenAll: widget.onOpenChat,
                ),
                const SizedBox(height: 12),
              ],
              StatusBox(bluetoothOn: mesh.bluetoothOn, scanningOk: scanningOk),
              // Tonight'''s halt, above the general Seva list: by evening it
              // is the thing a walking Warkari most wants. Renders nothing
              // when no halt has been announced — see MukkaamCard.
              if (mesh.mukkaamPoints.isNotEmpty) ...[
                const SizedBox(height: 12),
                MukkaamCard(
                  halts: mesh.mukkaamPoints,
                  onTap: (point) => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          HelpPointDetailScreen(mesh: mesh, point: point),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SectionHeader(title: t.nearbySeva),
              NearbySevaCard(
                points: nearbySeva,
                onTap: (point) => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        HelpPointDetailScreen(mesh: mesh, point: point),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DindiCard(
                groupOrId: widget.warkari.groupOrId,
                headcount: mesh.dindiHeadcount,
                memberNames: mesh.dindiMemberNames,
                onDindiChanged: widget.onDindiChanged,
                isDindiLead: mesh.amDindiLead,
                onDindiLeadChanged: widget.onDindiLeadChanged,
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
                        title: t.sosSend,
                        subtitle: t.sosSubtitle,
                        onTap: widget.onOpenSos,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ActionBox(
                        color: AppColors.lostPerson,
                        icon: Icons.person_search,
                        title: t.missingTitle,
                        subtitle: activeMissing == 0
                            ? t.missingSubtitleIdle
                            : t.missingSubtitleActive(activeMissing),
                        badge: activeMissing == 0 ? null : mrNum(activeMissing),
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
