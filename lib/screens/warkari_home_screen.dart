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
import 'dindi_picker.dart';

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

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: Row(
            children: [
              const Icon(Icons.directions_walk),
              const SizedBox(width: 8),
              Text('Namaskar, ${widget.warkari.name.split(' ').first}'),
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
              _StatusBox(bluetoothOn: mesh.bluetoothOn, scanningOk: scanningOk),
              const SizedBox(height: 12),
              _DindiCard(
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
                      child: _ActionBox(
                        color: AppColors.sos,
                        icon: Icons.sos,
                        title: 'Send SOS',
                        subtitle: 'Alert nearby phones',
                        onTap: widget.onOpenSos,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionBox(
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
class _DindiCard extends StatelessWidget {
  final String groupOrId;
  final int headcount;
  final List<String> memberNames;
  final ValueChanged<String> onDindiChanged;

  const _DindiCard({
    required this.groupOrId,
    required this.headcount,
    required this.memberNames,
    required this.onDindiChanged,
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
                        Text(groupOrId, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
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
                'MEMBERS NEARBY',
                style: Theme.of(sheetContext).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 6),
              _MemberTile(name: 'You', isYou: true),
              ...memberNames.map((name) => _MemberTile(name: name)),
              if (memberNames.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'No one else from your Dindi is in range yet. Members appear here automatically when their phone is nearby.',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Join a different Dindi'),
                onPressed: () async {
                  Navigator.of(sheetContext).pop();
                  final name = await showDindiSheet(context, currentName: groupOrId);
                  if (name != null) onDindiChanged(name);
                },
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.sos),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Leave Dindi'),
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
                child: Icon(_hasDindi ? Icons.groups : Icons.group_add_outlined, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hasDindi ? groupOrId : 'Create or join a Dindi',
                      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 17),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color),
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
class _MemberTile extends StatelessWidget {
  final String name;
  final bool isYou;

  const _MemberTile({required this.name, this.isYou = false});

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
              style: const TextStyle(color: AppColors.relayed, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
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
class _StatusBox extends StatelessWidget {
  final bool bluetoothOn;
  final bool scanningOk;

  const _StatusBox({required this.bluetoothOn, required this.scanningOk});

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
          Icon(scanningOk ? Icons.sensors : Icons.sensors_off, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              !bluetoothOn
                  ? 'Bluetooth is off — turn it on to reach nearby phones'
                  : scanningOk
                      ? 'Connected to the mesh — nearby phones can hear you'
                      : 'Not connected yet',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: color),
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
class _ActionBox extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _ActionBox({
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
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        badge!,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
