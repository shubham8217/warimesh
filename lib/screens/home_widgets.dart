// WariMesh — the home-screen furniture shared by both roles.
//
// These started life inside warkari_home_screen.dart. The volunteer
// dashboard was written earlier, never got this layout, and so ended up
// without the Dindi card entirely — a volunteer literally could not join or
// change a Dindi from their own home screen. Rather than copy 300 lines
// across, both screens now build from the same pieces, so the two roles
// can't drift apart again.
import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'dindi_picker.dart';

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

  const DindiCard({
    super.key,
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
              MemberTile(name: 'You', isYou: true),
              ...memberNames.map((name) => MemberTile(name: name)),
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
class StatusBox extends StatelessWidget {
  final bool bluetoothOn;
  final bool scanningOk;

  const StatusBox({super.key, required this.bluetoothOn, required this.scanningOk});

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
