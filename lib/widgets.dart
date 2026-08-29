// WariMesh — small shared widgets used across screens.
import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

/// Maps an [AvatarPalette] icon index to a real, literal `Icons.*` constant.
/// Kept as an explicit switch (not a dynamic IconData) so release-mode icon
/// tree-shaking can never strip it — see the note in models.dart.
IconData avatarIconFor(int index) {
  switch (index % AvatarPalette.icons.length) {
    case 0:
      return Icons.person;
    case 1:
      return Icons.face;
    case 2:
      return Icons.child_care;
    case 3:
      return Icons.elderly;
    case 4:
      return Icons.boy;
    case 5:
      return Icons.girl;
    case 6:
      return Icons.man;
    case 7:
      return Icons.woman;
    default:
      return Icons.person;
  }
}

Color avatarColorFor(int index) =>
    Color(AvatarPalette.colors[index % AvatarPalette.colors.length]);

class LostPersonAvatar extends StatelessWidget {
  final int iconIndex;
  final int colorIndex;
  final double radius;
  final bool found;

  const LostPersonAvatar({
    super.key,
    required this.iconIndex,
    required this.colorIndex,
    this.radius = 28,
    this.found = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = avatarColorFor(colorIndex);
    return Stack(
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: color.withValues(alpha: found ? 0.25 : 0.15),
          child: Icon(avatarIconFor(iconIndex), color: found ? color.withValues(alpha: 0.6) : color, size: radius),
        ),
        if (found)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppColors.relayed,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(Icons.check, size: radius * 0.45, color: Colors.white),
            ),
          ),
      ],
    );
  }
}

class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const StatusPill({super.key, required this.text, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

class LogTile extends StatelessWidget {
  final LogEntry entry;
  const LogTile({super.key, required this.entry});

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'Sent':
        return Icons.north_east;
      case 'Received':
        return Icons.south_west;
      case 'Relayed':
        return Icons.sync_alt;
      case 'Final hop':
        return Icons.flag;
      case 'Advisory':
        return Icons.smart_toy_outlined;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forLogKind(entry.kind);
    final t = entry.time;
    final timeStr = '${_twoDigits(t.hour)}:${_twoDigits(t.minute)}:${_twoDigits(t.second)}';
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(_iconFor(entry.kind), size: 16, color: color),
      ),
      title: Text(entry.text, style: const TextStyle(fontSize: 13.5)),
      subtitle: Text(entry.kind, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
      trailing: Text(timeStr, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Expanded, not bare: a Row gives an unwrapped Text unbounded
          // width, so any title long enough to meet the trailing button
          // overflows the screen instead of shrinking. That was the
          // yellow-and-black overflow stripe on the volunteer dashboard.
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
