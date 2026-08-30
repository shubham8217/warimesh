// WariMesh — the volunteer's advisory desk.
//
// The protocol has carried advisories since text messaging was added
// (kTextKindAnnouncement): an announcement reaches every phone in range
// regardless of Dindi, unlike ordinary chat which is shown only to your own
// group. But the only way to send one was to open Dindi chat, find a toggle
// next to the composer, and type — which is the wrong shape for the job in
// two ways.
//
// First, typing. An advisory gets sent by someone standing in a crowd,
// often one-handed, sometimes in the dark, frequently in a hurry, into a
// 128-character limit they will discover halfway through a sentence. So the
// primary interface here is a grid of one-tap presets covering what
// volunteers actually announce. Free text stays available underneath for
// the thing no preset anticipated.
//
// Second, airtime. Chat repeats for 40 seconds, which is right for a
// conversation between people standing together. An advisory is aimed at
// people who have not arrived yet — the pilgrims who will walk past this
// camp in the next ten minutes — so it goes out with a much longer airtime
// (see sendText's airtime parameter for why that beats re-sending).
import 'package:flutter/material.dart';

import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';

/// A ready-made advisory. Wording is final, not a starting point — a preset
/// you have to edit is just a slower way to type.
class _Preset {
  final IconData icon;
  final String label;
  final String body;
  const _Preset(this.icon, this.label, this.body);
}

const List<_Preset> _kPresets = [
  _Preset(
    Icons.alt_route,
    'Route change',
    'Route diverted ahead. Follow volunteers in red. Do not turn back.',
  ),
  _Preset(
    Icons.water_drop_outlined,
    'Water point',
    'Water point ahead on the left. Free drinking water for all.',
  ),
  _Preset(
    Icons.no_drinks_outlined,
    'Water closed',
    'Water point ahead is closed. Next water is at the following halt.',
  ),
  _Preset(
    Icons.medical_services_outlined,
    'Medical camp',
    'Medical camp ahead. First aid, ORS and doctors available.',
  ),
  _Preset(
    Icons.groups_outlined,
    'Crowd ahead',
    'Heavy crowd ahead. Slow down, keep left, hold on to children.',
  ),
  _Preset(
    Icons.child_care_outlined,
    'Lost child desk',
    'Lost child desk at this camp. Bring any child found alone here.',
  ),
  _Preset(
    Icons.thunderstorm_outlined,
    'Weather',
    'Rain expected. Take shelter at the next halt if you can.',
  ),
  _Preset(
    Icons.night_shelter_outlined,
    'Halt for night',
    'Night halt at this camp. Food and sleeping space available.',
  ),
];

/// How long an advisory keeps repeating on the radio. See the file header.
const Duration _kAdvisoryAirtime = Duration(minutes: 5);

class AdvisoryScreen extends StatefulWidget {
  final MeshService mesh;
  const AdvisoryScreen({super.key, required this.mesh});

  @override
  State<AdvisoryScreen> createState() => _AdvisoryScreenState();
}

class _AdvisoryScreenState extends State<AdvisoryScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send(String body) async {
    if (_sending) return;
    setState(() => _sending = true);
    final ok = await widget.mesh.sendText(
      body,
      announcement: true,
      airtime: _kAdvisoryAirtime,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Advisory going out for ${_kAdvisoryAirtime.inMinutes} minutes'
              : 'Saved, but this phone could not broadcast it',
        ),
        backgroundColor: ok ? AppColors.relayed : AppColors.warning,
      ),
    );
  }

  Future<void> _confirmAndSend(String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send this advisory?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.demo.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                body,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              // An advisory buzzes every phone in range, including people
              // who are not in your Dindi and did not ask to hear from you.
              // Worth one tap of friction.
              'Every phone in range will be notified, in every Dindi.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (ok == true) await _send(body);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return CustomScrollView(
      slivers: [
        const SliverAppBar(floating: true, title: Text('Advisories')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.campaign_outlined,
                        color: AppColors.demo,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'An advisory reaches every phone in range, in every Dindi, '
                          'and repeats for ${_kAdvisoryAirtime.inMinutes} minutes so people '
                          'still walking towards you also hear it.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'One tap',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: muted,
                ),
              ),
              const SizedBox(height: 10),
              // A Wrap of content-sized tiles rather than a GridView with a
              // fixed childAspectRatio. The ratio was 2.1, which pinned every
              // tile to one height computed from the screen width -- so on a
              // narrower or denser phone the icon plus label did not fit and
              // the tile overflowed (seen as "BOTTOM OVERFLOWED BY 4.3
              // PIXELS" on a Redmi). Devanagari sits taller than Latin, which
              // makes a fixed ratio wrong in principle here, not just on one
              // handset: the tile must size to its text, not the other way
              // round.
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 10.0;
                  final tileWidth = (constraints.maxWidth - spacing) / 2;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final preset in _kPresets)
                        SizedBox(
                          width: tileWidth,
                          child: _PresetTile(
                            preset: preset,
                            enabled: !_sending,
                            onTap: () => _confirmAndSend(preset.body),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Something else',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: muted,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _controller,
                maxLength: kMaxTextLength,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText:
                      'Short and specific — people read this while walking',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_sending || _controller.text.trim().isEmpty)
                      ? null
                      : () => _confirmAndSend(_controller.text.trim()),
                  icon: const Icon(Icons.campaign, size: 20),
                  label: const Text('Broadcast advisory'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_open, size: 15, color: muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      // The same warning the chat screen carries, and it
                      // belongs here too: a volunteer broadcasting to a
                      // crowd should know the crowd is not the only audience.
                      'Nothing here is private. A Bluetooth advertisement is public — '
                      'anyone in range with a scanner can read it, WariMesh user or not.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                ],
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _PresetTile extends StatelessWidget {
  final _Preset preset;
  final bool enabled;
  final VoidCallback onTap;

  const _PresetTile({
    required this.preset,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(preset.icon, color: AppColors.demo, size: 24),
              const SizedBox(height: 8),
              Text(
                preset.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
                // Two lines, because a Marathi label is longer than its
                // English counterpart and truncating the one word that says
                // what the advisory IS makes the tile useless.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
