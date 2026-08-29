// WariMesh — full detail view for one missing-person report: description,
// broadcast status, and the "mark as found" action.
import 'package:flutter/material.dart';

import '../database_service.dart';
import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class LostPersonDetailScreen extends StatefulWidget {
  final MeshService mesh;
  final LostReport report;
  const LostPersonDetailScreen({super.key, required this.mesh, required this.report});

  @override
  State<LostPersonDetailScreen> createState() => _LostPersonDetailScreenState();
}

class _LostPersonDetailScreenState extends State<LostPersonDetailScreen> {
  late LostReport _report = widget.report;
  bool _busy = false;

  Future<void> _rebroadcast() async {
    setState(() => _busy = true);
    final packet = await widget.mesh.sendAlert(
      kCategoryLostPerson,
      lostName: _report.name,
      lostAge: _report.age,
    );
    if (packet != null && _report.id != null) {
      await LostReportsDb.setBroadcast(_report.id!, packet.msgId, DateTime.now());
      setState(() => _report = _report.copyWith(msgId: packet.msgId, broadcastAt: DateTime.now()));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggleFound() async {
    if (_report.id == null) return;
    final newFound = !_report.found;
    await LostReportsDb.setFound(_report.id!, newFound);
    widget.mesh.appendLog(
      newFound ? '🎉 ${_report.name} marked as FOUND' : '${_report.name} marked as still missing',
      newFound ? 'Relayed' : 'Warning',
    );

    // Marking someone found used to be a purely local act: this phone's
    // list changed and every other phone on the Wari kept relaying "look
    // out for this person" for as long as the alert had airtime. If the
    // report was ever broadcast, closing it has to go out too — that is the
    // whole reason RESOLVE exists (see kResolvePacketType).
    final msgId = _report.msgId;
    if (msgId != null) {
      if (newFound) {
        await widget.mesh.resolveByMsgId(msgId);
      } else {
        // Reopening is local-only on purpose. There is no "un-resolve"
        // packet, and inventing one would let a single phone restart a
        // search across the whole route. Rebroadcast is the deliberate,
        // visible way to put the alert back on the air.
        widget.mesh.appendLog(
          'Reopened locally — use Broadcast again to put it back on the mesh',
          'Warning',
        );
      }
    }

    setState(() => _report = _report.copyWith(found: newFound));
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
      appBar: AppBar(title: Text(r.name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: LostPersonAvatar(iconIndex: r.avatarIconIndex, colorIndex: r.avatarColorIndex, radius: 48, found: r.found)),
          const SizedBox(height: 12),
          Center(
            child: Text('${r.name}${r.age.isNotEmpty ? ' · ${r.age}' : ''}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 8),
          Center(
            child: Wrap(
              spacing: 8,
              children: [
                if (r.found)
                  const StatusPill(text: 'FOUND', color: AppColors.relayed, icon: Icons.check_circle)
                else if (r.broadcastAt != null)
                  const StatusPill(text: 'BROADCAST', color: AppColors.lostPerson, icon: Icons.podcasts)
                else
                  const StatusPill(text: 'NOT BROADCAST YET', color: AppColors.warning, icon: Icons.drafts),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _DetailCard(icon: Icons.notes_outlined, label: 'Description', value: r.description),
          if (r.lastSeenLocation.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DetailCard(icon: Icons.place_outlined, label: 'Last seen', value: r.lastSeenLocation),
          ],
          if (r.contactInfo.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DetailCard(icon: Icons.call_outlined, label: 'Contact', value: r.contactInfo),
          ],
          if (r.broadcastAt != null) ...[
            const SizedBox(height: 10),
            _DetailCard(
              icon: Icons.podcasts,
              label: 'Broadcast',
              value: 'Sent as msg #${r.msgId} · ${r.broadcastAt}',
            ),
          ],
          const SizedBox(height: 28),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: r.found ? AppColors.warning : AppColors.relayed),
            onPressed: _toggleFound,
            icon: Icon(r.found ? Icons.undo : Icons.check_circle_outline),
            label: Text(r.found ? 'Mark as still missing' : 'Mark as found'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy || r.found ? null : _rebroadcast,
            icon: const Icon(Icons.campaign_outlined),
            label: Text(r.broadcastAt == null ? 'Broadcast alert now' : 'Broadcast again'),
          ),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 3),
                  Text(value),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
