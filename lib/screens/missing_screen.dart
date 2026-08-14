// WariMesh — list of missing-person reports on this phone, with a form to
// add new ones. This is local-only data (see the honesty note in
// models.dart) — broadcasting sends a lightweight beacon over the mesh so
// nearby responders know to look out for someone; the full description
// stays on the reporting phone until shown directly.
import 'package:flutter/material.dart';

import '../database_service.dart';
import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'lost_person_detail_screen.dart';
import 'report_form_screen.dart';

class MissingScreen extends StatefulWidget {
  final MeshService mesh;
  const MissingScreen({super.key, required this.mesh});

  @override
  State<MissingScreen> createState() => _MissingScreenState();
}

class _MissingScreenState extends State<MissingScreen> {
  List<LostReport> _reports = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final reports = await LostReportsDb.all();
      if (mounted) {
        setState(() {
          _reports = reports;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _reports.where((r) => !r.found).toList();
    final found = _reports.where((r) => r.found).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Missing persons'), automaticallyImplyLeading: false),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Report someone missing'),
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => ReportFormScreen(mesh: widget.mesh)),
          );
          if (saved == true) _load();
        },
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
              ? _EmptyState(onAdd: () async {
                  final saved = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => ReportFormScreen(mesh: widget.mesh)),
                  );
                  if (saved == true) _load();
                })
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    if (active.isNotEmpty) ...[
                      Text('Active (${active.length})', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      ...active.map((r) => _ReportCard(report: r, onTap: () => _openDetail(r))),
                    ],
                    if (found.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text('Found (${found.length})', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      ...found.map((r) => _ReportCard(report: r, onTap: () => _openDetail(r))),
                    ],
                  ],
                ),
    );
  }

  Future<void> _openDetail(LostReport r) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LostPersonDetailScreen(mesh: widget.mesh, report: r)),
    );
    _load();
  }
}

class _ReportCard extends StatelessWidget {
  final LostReport report;
  final VoidCallback onTap;
  const _ReportCard({required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LostPersonAvatar(iconIndex: report.avatarIconIndex, colorIndex: report.avatarColorIndex, found: report.found),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${report.name} · ${report.age}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(report.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (report.found)
                            const StatusPill(text: 'FOUND', color: AppColors.relayed, icon: Icons.check_circle)
                          else if (report.broadcastAt != null)
                            const StatusPill(text: 'BROADCAST', color: AppColors.lostPerson, icon: Icons.podcasts)
                          else
                            const StatusPill(text: 'NOT BROADCAST', color: AppColors.warning, icon: Icons.drafts),
                          if (report.lastSeenLocation.isNotEmpty)
                            StatusPill(text: report.lastSeenLocation, color: Colors.grey.shade700, icon: Icons.place_outlined),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('No missing-person reports yet', style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Add a name, description, and last-seen location so nearby responders know who to look for.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Report someone missing')),
          ],
        ),
      ),
    );
  }
}
