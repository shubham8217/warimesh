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
import '../widgets.dart';

class WarkariHomeScreen extends StatefulWidget {
  final MeshService mesh;
  final UserProfile warkari;
  final VoidCallback onLogout;
  final VoidCallback onOpenSos;
  final VoidCallback onOpenMissing;

  const WarkariHomeScreen({
    super.key,
    required this.mesh,
    required this.warkari,
    required this.onLogout,
    required this.onOpenSos,
    required this.onOpenMissing,
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
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        scanningOk ? Icons.sensors : Icons.sensors_off,
                        color: scanningOk ? AppColors.relayed : Colors.grey,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          !mesh.bluetoothOn
                              ? 'Bluetooth is off — turn it on to reach nearby phones'
                              : scanningOk
                                  ? 'Connected to the mesh — nearby phones can hear you'
                                  : 'Not connected yet',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SectionHeader(title: 'What do you need?'),
              _BigActionCard(
                color: AppColors.sos,
                icon: Icons.sos,
                title: 'Send SOS',
                subtitle: 'Alert nearby phones that you need help',
                onTap: widget.onOpenSos,
              ),
              const SizedBox(height: 12),
              _BigActionCard(
                color: AppColors.lostPerson,
                icon: Icons.person_search,
                title: 'Missing persons',
                subtitle: activeMissing == 0
                    ? 'Report someone missing, or check who\'s been reported'
                    : '$activeMissing active report${activeMissing == 1 ? '' : 's'} — tap to view',
                onTap: widget.onOpenMissing,
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _BigActionCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _BigActionCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
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
          child: Row(
            children: [
              CircleAvatar(radius: 26, backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color, size: 26)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 17)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
