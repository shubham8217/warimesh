// WariMesh — the volunteer's relay ops panel.
//
// Everything here already existed; what's new is that it is no longer on
// the home screen. Mesh diagnostics are reference information a volunteer
// consults occasionally — "is my phone actually relaying?" — not something
// they act on every time they open the app, and a dashboard whose top half
// is diagnostics teaches people to scroll past the part that matters.
//
// The framing is deliberate: a volunteer's phone is infrastructure. It sits
// at a camp while a hundred thousand people walk past it, and its job is to
// hear alerts and pass them on. This screen answers whether it is doing
// that job.
import 'package:flutter/material.dart';

import '../mesh_service.dart';
import '../theme.dart';
import '../widgets.dart';
import 'activity_log_screen.dart';

class OpsScreen extends StatelessWidget {
  final MeshService mesh;
  const OpsScreen({super.key, required this.mesh});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final canRelay = mesh.scanning && mesh.bluetoothOn;

    return CustomScrollView(
      slivers: [
        const SliverAppBar(floating: true, title: Text('Relay status')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _HeadlineCard(mesh: mesh, canRelay: canRelay),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _OpsLine(
                        icon: mesh.bluetoothOn ? Icons.bluetooth : Icons.bluetooth_disabled,
                        color: mesh.bluetoothOn ? AppColors.relayed : AppColors.sos,
                        title: mesh.bluetoothOn ? 'Bluetooth on' : 'Bluetooth off',
                        detail: mesh.bluetoothOn
                            ? 'The radio is available'
                            : 'Nothing can be sent or received until this is turned on',
                      ),
                      const Divider(height: 24),
                      _OpsLine(
                        icon: mesh.scanning ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                        color: mesh.scanning ? AppColors.relayed : AppColors.warning,
                        title: mesh.scanning ? 'Listening' : 'Not listening',
                        detail: mesh.scanning
                            ? 'Picking up alerts from phones in range'
                            : 'This phone is not hearing anything right now',
                      ),
                      const Divider(height: 24),
                      _OpsLine(
                        icon: mesh.peripheralSupported ? Icons.podcasts : Icons.error_outline,
                        color: mesh.peripheralSupported ? AppColors.relayed : AppColors.warning,
                        title: mesh.peripheralSupported ? 'Can transmit' : 'Receive only',
                        // This is the single most important line on the
                        // screen when it reads "Receive only": a phone that
                        // cannot advertise looks completely normal, relays
                        // nothing, and answers nobody. Emulators and some
                        // real handsets have no BLE peripheral mode at all.
                        detail: mesh.peripheralSupported
                            ? 'This phone relays what it hears, and can answer alerts'
                            : 'This phone has no Bluetooth transmit mode — it can hear '
                                'alerts but cannot relay them or tell anyone it is responding',
                      ),
                      const Divider(height: 24),
                      _OpsLine(
                        icon: mesh.backgroundServiceEnabled
                            ? Icons.shield_outlined
                            : Icons.shield_moon_outlined,
                        color: mesh.backgroundServiceEnabled ? AppColors.relayed : AppColors.warning,
                        title: mesh.backgroundServiceEnabled
                            ? 'Relaying with the screen off'
                            : 'Stops when the screen locks',
                        detail: mesh.backgroundServiceEnabled
                            ? 'The background service is running'
                            : 'Alerts arriving while the phone is in a pocket may be missed',
                      ),
                      const Divider(height: 24),
                      _OpsLine(
                        icon: Icons.storage_outlined,
                        color: muted,
                        title: '${mesh.seenCount} alerts handled',
                        detail: 'Kept on this phone, so an alert seen before a '
                            'restart is not treated as new afterwards',
                      ),
                      const Divider(height: 24),
                      _OpsLine(
                        icon: mesh.hasLocationFix ? Icons.my_location : Icons.location_searching,
                        color: mesh.hasLocationFix ? AppColors.relayed : muted,
                        title: mesh.hasLocationFix ? 'Location fix' : 'No location fix',
                        detail: mesh.hasLocationFix
                            ? 'Incoming alerts can be shown with a distance and direction'
                            : 'Alerts will arrive without a distance until GPS settles',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                value: mesh.backgroundServiceEnabled,
                onChanged: (v) => mesh.toggleBackgroundService(v),
                title: const Text('Background relay', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text(
                  'Keeps hearing and passing on alerts when the screen is off. '
                  'Leave this on unless the battery is critical.',
                ),
                tileColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
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
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.sensors, size: 22, color: muted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Nothing heard yet. This is normal until another phone is in range.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Card(
                  child: Column(
                    children: mesh.log.take(6).map((e) => LogTile(entry: e)).toList(),
                  ),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

/// One sentence at the top answering the only question that matters, in
/// letters big enough to read at arm's length.
class _HeadlineCard extends StatelessWidget {
  final MeshService mesh;
  final bool canRelay;
  const _HeadlineCard({required this.mesh, required this.canRelay});

  @override
  Widget build(BuildContext context) {
    final color = canRelay ? AppColors.relayed : AppColors.sos;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(canRelay ? Icons.hub : Icons.link_off, color: color, size: 30),
          const SizedBox(height: 12),
          Text(
            canRelay ? 'Your phone is part of the mesh' : 'Your phone is off the mesh',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            canRelay
                ? 'It is listening for alerts and passing on what it hears, '
                    'whether or not you are looking at it.'
                : 'It is not hearing or relaying anything. Turn Bluetooth on.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _OpsLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  const _OpsLine({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
