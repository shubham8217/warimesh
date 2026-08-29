// WariMesh — "What do you need help with?"
//
// The one question between holding the SOS button and the alert going out.
// It exists because "someone needs help" is barely actionable in a crowd of
// a hundred thousand people, while "heat, 200 m north-east" tells a
// volunteer what to carry and where to run.
//
// Every design choice here is about the two seconds it costs:
//
//  - Seven fixed choices, no typing, no free text, no "add details" field.
//    A person having a medical emergency is not filling in a form, and an
//    optional field that delays an emergency is not optional.
//  - Full-width rows with a large glyph, not a grid of small chips —
//    thumb-sized targets for someone walking, shaking, or holding a child.
//  - Dismissing the sheet does NOT cancel the SOS. Backing out, dropping the
//    phone, or a stray tap outside sends the alert anyway, as
//    kSosReasonUnspecified — which is exactly what every SOS was before
//    reasons existed. The alert is the thing that must never be lost; the
//    reason is an improvement on top of it and is never allowed to become a
//    gate in front of it.
import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Asks what kind of emergency this is. Always resolves to a reason —
/// [kSosReasonUnspecified] if the person dismissed the sheet without
/// choosing, which still sends a perfectly valid SOS.
Future<int> askSosReason(BuildContext context) async {
  final picked = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    // Not dismissible by dragging alone would be wrong here — see the note
    // above about never gating the alert. Dismissing is a valid answer.
    builder: (context) => const _SosReasonSheet(),
  );
  return picked ?? kSosReasonUnspecified;
}

class _SosReasonSheet extends StatelessWidget {
  const _SosReasonSheet();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'What do you need help with?',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
            const SizedBox(height: 4),
            Text(
              'Your alert goes out either way. This tells whoever answers '
              'what to bring.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 14),
            for (final reason in kSosReasons)
              _ReasonRow(
                reason: reason,
                onTap: () => Navigator.of(context).pop(reason),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(kSosReasonUnspecified),
              child: const Text("Send without saying"),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonRow extends StatelessWidget {
  final int reason;
  final VoidCallback onTap;

  const _ReasonRow({required this.reason, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Critical reasons carry the SOS red; the rest stay neutral. The colour
    // is a hint, never a ranking a person has to decode — all seven are one
    // tap away and none is hidden behind another.
    final critical = sosReasonPriority(reason) == kSosPriorityCritical;
    final color = critical ? AppColors.sos : AppColors.lostPerson;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            // Tall rows on purpose: this is tapped by people who are
            // frightened, elderly, or moving.
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Text(
                  sosReasonEmoji(reason),
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    sosReasonLabel(reason),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
