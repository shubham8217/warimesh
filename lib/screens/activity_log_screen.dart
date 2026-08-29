// WariMesh — full mesh activity feed. Real mesh traffic only.
//
// This screen used to carry a "Simulate incoming alert" button that fed a
// synthetic packet through the receive pipeline, for demonstrating a
// notification without a second phone. It went with Demo Mode: with real
// devices to test against, an activity log that mixes invented traffic with
// real traffic can make a broken mesh look healthy.
import 'package:flutter/material.dart';

import '../mesh_service.dart';
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
        );
      },
    );
  }
}
