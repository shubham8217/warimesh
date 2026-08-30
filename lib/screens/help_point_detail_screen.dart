// WariMesh — full detail view for one help point reached over the Wari Seva
// Network (see HelpPointRecord in models.dart). Read-only except for the
// "I'm going there" acknowledgement, which never leaves this phone — see
// the note on HelpPointRecord.acknowledged.
import 'package:flutter/material.dart';

import '../directions.dart';
import '../l10n/app_strings.dart';
import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';

class HelpPointDetailScreen extends StatefulWidget {
  final MeshService mesh;
  final HelpPointRecord point;
  const HelpPointDetailScreen({
    super.key,
    required this.mesh,
    required this.point,
  });

  @override
  State<HelpPointDetailScreen> createState() => _HelpPointDetailScreenState();
}

class _HelpPointDetailScreenState extends State<HelpPointDetailScreen> {
  late final HelpPointRecord _point = widget.point;

  static const Map<int, IconData> _icons = {
    kStationMedical: Icons.medical_services,
    kStationWater: Icons.water_drop,
    kStationFood: Icons.restaurant,
    kStationLostChildDesk: Icons.child_care,
    kStationPolice: Icons.local_police,
    kStationToilet: Icons.wc,
    kStationNightHalt: Icons.bedtime,
    kStationCharging: Icons.charging_station,
    kStationFirstAid: Icons.health_and_safety,
    kStationOther: Icons.info,
  };

  Color get _statusColor {
    if (_point.isClosed) return AppColors.neutral;
    if (_point.isLimited) return AppColors.warning;
    return AppColors.relayed;
  }

  /// Hands the help point's coordinates to a maps app, exactly as the alert
  /// overlay does for an SOS. Only reachable when hasLocation is true.
  Future<void> _openDirections(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final opened = await openWalkingDirections(
      _point.latitude!,
      _point.longitude!,
    );
    if (opened || !context.mounted) return;
    messenger?.showSnackBar(SnackBar(content: Text(t.noMapsApp)));
  }

  Future<void> _iAmGoing() async {
    await widget.mesh.acknowledgeHelpPoint(_point);
    _point.acknowledged = true;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final icon = _icons[_point.helpType] ?? Icons.help_outline;

    return Scaffold(
      appBar: AppBar(title: Text(t.station(_point.helpType))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: _statusColor.withValues(alpha: 0.15),
                    child: Icon(icon, color: _statusColor, size: 30),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    t.stationAvailable(t.station(_point.helpType)),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: _statusColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      t.helpStatus(_point.status),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: _statusColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoLine(
                      icon: Icons.podcasts,
                      title: t.sharedThroughWariMesh,
                      detail: _point.hops == 0
                          ? t.receivedDirectly
                          : t.relayedThrough(_point.hops),
                    ),
                    const Divider(height: 24),
                    const Divider(height: 24),
                    _InfoLine(
                      icon: _point.distanceLabel == null
                          ? Icons.location_off_outlined
                          : Icons.near_me,
                      title: _point.distanceMetres == null
                          ? t.place
                          : t.distance(_point.distanceMetres!),
                      // Never fabricated — see AppStrings.whereLabel.
                      detail: t.whereLabel(
                        hasLocation: _point.hasLocation,
                        distanceMetres: _point.distanceMetres,
                        bearingDegrees: _point.bearingDegrees,
                      ),
                    ),
                    const Divider(height: 24),
                    _InfoLine(
                      icon: Icons.schedule,
                      title: t.lastUpdated,
                      detail: t.ageLabel(_point.receivedAt),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              t.helpPointPrivacyNote,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 24),
            // Directions only when there is a real position to hand over —
            // an offer to navigate to nowhere is worse than no offer.
            if (!_point.isClosed && _point.hasLocation) ...[
              FilledButton.icon(
                onPressed: () => _openDirections(context),
                icon: const Icon(Icons.directions_walk),
                label: Text(t.openDirections),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppColors.relayed,
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (!_point.isClosed)
              FilledButton.icon(
                onPressed: _point.acknowledged ? null : _iAmGoing,
                icon: Icon(
                  _point.acknowledged ? Icons.check : Icons.directions_walk,
                ),
                label: Text(
                  _point.acknowledged ? t.youreOnYourWay : t.imGoingThere,
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppColors.relayed,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  const _InfoLine({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: muted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
