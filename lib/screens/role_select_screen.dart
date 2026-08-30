// WariMesh — the very first screen: pick who's signing in. A warkari
// (pilgrim) and a volunteer see different views of the app afterwards —
// see main.dart's AuthGate for how the choice made here is routed.
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models.dart';
import '../theme.dart';

class RoleSelectScreen extends StatelessWidget {
  final ValueChanged<UserRole> onRoleChosen;
  const RoleSelectScreen({super.key, required this.onRoleChosen});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
          child: Column(
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.sos.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hub, size: 48, color: AppColors.sos),
              ),
              const SizedBox(height: 20),
              const Text(
                'WariMesh',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Who\'s signing in?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 32),
              _RoleCard(
                icon: Icons.directions_walk,
                color: AppColors.lostPerson,
                title: 'Warkari',
                subtitle:
                    'Walking the Wari — send an SOS or check who\'s missing',
                onTap: () => onRoleChosen(UserRole.warkari),
              ),
              const SizedBox(height: 14),
              _RoleCard(
                icon: Icons.support_agent,
                color: AppColors.sos,
                title: 'Volunteer',
                subtitle:
                    'Camp staff — answer alerts, run a help point, send advisories',
                onTap: () => onRoleChosen(UserRole.volunteer),
              ),
              const Spacer(),
              // Before sign-in, and visible without opening anything. See
              // LanguageToggle for why this cannot live behind a menu.
              const LanguageToggle(),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
