// WariMesh — dashboard: mesh status at a glance, quick actions, recent
// activity preview, and how many people are still marked missing.
import 'package:flutter/material.dart';

import '../database_service.dart';
import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'activity_log_screen.dart';

class HomeScreen extends StatefulWidget {
  final MeshService mesh;
  final VoidCallback onOpenSos;
  final VoidCallback onOpenMissing;

  const HomeScreen({super.key, required this.mesh, required this.onOpenSos, required this.onOpenMissing});

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

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: Row(
            children: [
              const Icon(Icons.hub_outlined),
              const SizedBox(width: 8),
              Text('WariMesh · ${mesh.deviceLabel}'),
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
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _StatusCard(mesh: mesh, onRefresh: _load),
              const SizedBox(height: 20),
              SectionHeader(title: 'Quick actions'),
              Row(
                children: [
                  Expanded(
                    child: _ActionCard(
                      color: AppColors.sos,
                      icon: Icons.sos,
                      label: 'Send SOS',
                      onTap: widget.onOpenSos,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionCard(
                      color: AppColors.lostPerson,
                      icon: Icons.person_search,
                      label: 'Report Missing',
                      onTap: widget.onOpenMissing,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SectionHeader(
                title: activeMissing == 0 ? 'No active missing-person reports' : '$activeMissing active missing-person report${activeMissing == 1 ? '' : 's'}',
                trailing: TextButton(onPressed: widget.onOpenMissing, child: const Text('View all')),
              ),
              if (_reports.isEmpty)
                _EmptyHint(
                  icon: Icons.person_search,
                  text: 'When someone goes missing, add their description here so nearby responders know who to look for.',
                )
              else
                ..._reports.take(3).map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MissingPreviewTile(report: r),
                    )),
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
                _EmptyHint(icon: Icons.sensors, text: 'No mesh activity yet. Send an SOS or Report Missing to get started.')
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

class _StatusCard extends StatelessWidget {
  final MeshService mesh;
  final VoidCallback onRefresh;
  const _StatusCard({required this.mesh, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final scanningOk = mesh.scanning && mesh.bluetoothOn;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  scanningOk ? Icons.sensors : Icons.sensors_off,
                  color: scanningOk ? AppColors.relayed : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    !mesh.bluetoothOn
                        ? 'Bluetooth is off'
                        : scanningOk
                            ? 'Listening for mesh traffic'
                            : 'Not scanning',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                if (mesh.demoMode) const StatusPill(text: 'DEMO MODE', color: AppColors.demo, icon: Icons.smart_toy_outlined),
              ],
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: mesh.peripheralSupported ? Icons.check_circle_outline : Icons.info_outline,
              text: mesh.peripheralSupported
                  ? 'This device can send + relay over real BLE'
                  : 'Real BLE advertising isn\'t available on this device/emulator — Demo Mode covers the send/receive flow for filming',
            ),
            const SizedBox(height: 4),
            _InfoRow(icon: Icons.storage_outlined, text: '${mesh.seenCount} messages seen (persisted on-device)'),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Demo mode', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Simulates nearby phones so send/receive always demos reliably, even solo'),
              value: mesh.demoMode,
              onChanged: (v) {
                mesh.demoMode = v;
                mesh.appendLog(v ? 'Demo Mode turned on' : 'Demo Mode turned off', 'Demo');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionCard({required this.color, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissingPreviewTile extends StatelessWidget {
  final LostReport report;
  const _MissingPreviewTile({required this.report});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: LostPersonAvatar(iconIndex: report.avatarIconIndex, colorIndex: report.avatarColorIndex, radius: 20, found: report.found),
        title: Text(report.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(report.description, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: report.found
            ? const StatusPill(text: 'FOUND', color: AppColors.relayed, icon: Icons.check_circle)
            : (report.broadcastAt != null
                ? const StatusPill(text: 'BROADCAST', color: AppColors.lostPerson, icon: Icons.podcasts)
                : const StatusPill(text: 'DRAFT', color: AppColors.warning)),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
          ],
        ),
      ),
    );
  }
}
