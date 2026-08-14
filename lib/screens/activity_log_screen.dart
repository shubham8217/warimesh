// WariMesh — full mesh activity feed, plus a manual "simulate incoming
// alert" demo control so a receive + notification can be shown on camera
// without needing a second phone.
import 'package:flutter/material.dart';

import '../mesh_service.dart';
import '../models.dart';
import '../widgets.dart';

class ActivityLogScreen extends StatelessWidget {
  final MeshService mesh;
  const ActivityLogScreen({super.key, required this.mesh});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: mesh,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Activity log')),
          body: mesh.log.isEmpty
              ? const Center(child: Text('No mesh activity yet'))
              : ListView.builder(
                  itemCount: mesh.log.length,
                  itemBuilder: (context, i) => LogTile(entry: mesh.log[i]),
                ),
          floatingActionButton: mesh.demoMode
              ? FloatingActionButton.extended(
                  icon: const Icon(Icons.smart_toy_outlined),
                  label: const Text('Simulate incoming'),
                  onPressed: () => _showSimulatePicker(context),
                )
              : null,
        );
      },
    );
  }

  void _showSimulatePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Simulate an incoming alert', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Feeds a fake nearby-phone packet through the real receive pipeline — notification, dedup, relay decision. Great for demoing without a second device.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.sos),
                      label: const Text('SOS'),
                      onPressed: () {
                        Navigator.pop(context);
                        mesh.simulateIncomingAlert(kCategorySos);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.person_search),
                      label: const Text('Lost Person'),
                      onPressed: () {
                        Navigator.pop(context);
                        mesh.simulateIncomingAlert(kCategoryLostPerson);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
