// WariMesh — the volunteer's home screen.
//
// Built from the same pieces as the warkari home (see home_widgets.dart):
// slim status strip, Dindi card, then the two things anyone actually needs
// in a hurry, side by side. This screen used to be an older dashboard that
// never received that work — most importantly it had no Dindi card at all,
// so a volunteer could not join or change a Dindi from their own home.
//
// What a volunteer gets on top of the warkari layout is the mesh detail
// they're the ones who care about: whether this phone can transmit, how
// much it has relayed, whether the background relay is alive, and a preview
// of the activity feed with a way into the full log. A warkari is
// deliberately shown none of that — it's noise to someone who just needs
// help.
import 'package:flutter/material.dart';

import '../database_service.dart';
import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'activity_log_screen.dart';
import 'home_widgets.dart';

class HomeScreen extends StatefulWidget {
  final MeshService mesh;
  final UserProfile volunteer;
  final VoidCallback onLogout;
  final VoidCallback onOpenSos;
  final VoidCallback onOpenMissing;
  final ValueChanged<String> onDindiChanged;

  const HomeScreen({
    super.key,
    required this.mesh,
    required this.volunteer,
    required this.onLogout,
    required this.onOpenSos,
    required this.onOpenMissing,
    required this.onDindiChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
      // Local DB unavailable (e.g. host test environment) — leave the list
      // empty rather than crash the dashboard.
    }
  }

  @override
  Widget build(BuildContext context) {
    final mesh = widget.mesh;
    final activeMissing = _reports.where((r) => !r.found).length;
    final scanningOk = mesh.scanning && mesh.bluetoothOn;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: Row(
            children: [
              const Icon(Icons.hub_outlined),
              const SizedBox(width: 8),
              // Flexible + ellipsis: this bar carries two action buttons, so
              // the title has less room than the warkari one, and an
              // unconstrained Text in a Row overflows rather than truncating.
              Flexible(
                child: Text(
                  'WariMesh · ${mesh.deviceLabel}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Activity log',
              icon: const Icon(Icons.history),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ActivityLogScreen(mesh: mesh)),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Volunteer',
              icon: const Icon(Icons.person_outline),
              onSelected: (v) {
                if (v == 'logout') widget.onLogout();
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(widget.volunteer.name, style: const TextStyle(fontWeight: FontWeight.w700)),
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
              StatusBox(bluetoothOn: mesh.bluetoothOn, scanningOk: scanningOk),
              const SizedBox(height: 12),
              DindiCard(
                groupOrId: widget.volunteer.groupOrId,
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

              // ---- volunteer-only from here down ----
              const SizedBox(height: 20),
              _MeshDetailBox(mesh: mesh),
              const SizedBox(height: 20),
              SectionHeader(
                title: 'Recent activity',
                trailing: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ActivityLogScreen(mesh: mesh)),
                  ),
                  child: const Text('View all'),
                ),
              ),
              if (mesh.log.isEmpty)
                const _EmptyHint(
                  icon: Icons.sensors,
                  text: 'No mesh activity yet. Send an SOS or report someone missing to get started.',
                )
              else
                Card(
                  child: Column(
                    children: mesh.log.take(4).map((e) => LogTile(entry: e)).toList(),
                  ),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

/// The facts a volunteer needs that a warkari doesn't: can this phone
/// actually transmit, how much has it handled, and is the background relay
/// alive. Deliberately quiet — it's reference information, not an action.
class _MeshDetailBox extends StatelessWidget {
  final MeshService mesh;
  const _MeshDetailBox({required this.mesh});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailLine(
            icon: mesh.peripheralSupported ? Icons.check_circle_outline : Icons.error_outline,
            color: mesh.peripheralSupported ? AppColors.relayed : AppColors.warning,
            text: mesh.peripheralSupported
                ? 'This phone can send and relay over real BLE'
                : 'This phone can receive alerts but never send them',
          ),
          const SizedBox(height: 8),
          _DetailLine(
            icon: Icons.storage_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            text: '${mesh.seenCount} messages seen (kept on this phone)',
          ),
          const SizedBox(height: 8),
          _DetailLine(
            icon: mesh.backgroundServiceEnabled ? Icons.shield_outlined : Icons.shield_moon_outlined,
            color: mesh.backgroundServiceEnabled ? AppColors.relayed : AppColors.warning,
            text: mesh.backgroundServiceEnabled
                ? 'Relaying in the background, even with the screen off'
                : 'Background relay is not running — alerts may be missed with the screen off',
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _DetailLine({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
