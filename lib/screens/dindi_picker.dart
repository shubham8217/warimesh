// WariMesh — Create-vs-Join UI for a warkari's Dindi, shown from the Home
// screen (not at sign-in — a person can pick or change their Dindi any
// time). "Join" can only list Dindi names THIS phone already knows about
// (see KnownDindisDb in database_service.dart) — there's no server, so a
// real cross-phone directory is the natural extension once cloud sync
// exists, not something built here yet.
import 'package:flutter/material.dart';

import '../database_service.dart';
import '../models.dart';

/// Opens a modal bottom sheet to create or join a Dindi. Returns the chosen
/// name, or null if the sheet was dismissed without picking one.
Future<String?> showDindiSheet(BuildContext context, {required String currentName}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _DindiSheet(currentName: currentName),
  );
}

class _DindiSheet extends StatefulWidget {
  final String currentName;
  const _DindiSheet({required this.currentName});

  @override
  State<_DindiSheet> createState() => _DindiSheetState();
}

class _DindiSheetState extends State<_DindiSheet> {
  late final _nameController = TextEditingController(text: widget.currentName == '—' ? '' : widget.currentName);
  bool _joiningExisting = false;
  List<String> _knownDindis = [];

  @override
  void initState() {
    super.initState();
    _loadKnownDindis();
  }

  Future<void> _loadKnownDindis() async {
    try {
      final names = await KnownDindisDb.all();
      if (mounted) setState(() => _knownDindis = names);
    } catch (_) {
      // Local DB unavailable — Join still works by typing a name.
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    try {
      await KnownDindisDb.remember(name);
    } catch (_) {
      // Non-fatal — the Dindi still applies to this session even if it
      // couldn't be remembered for next time's Join list.
    }
    if (mounted) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Your Dindi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 4),
          const Text(
            'Everyone in the same Dindi hears each other\'s SOS as a loud alert. Outside your Dindi, it\'s still relayed but shown quietly in the log.',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Create a Dindi'), icon: Icon(Icons.add_circle_outline)),
              ButtonSegment(value: true, label: Text('Join a Dindi'), icon: Icon(Icons.groups_outlined)),
            ],
            selected: {_joiningExisting},
            onSelectionChanged: (s) => setState(() {
              _joiningExisting = s.first;
              _nameController.clear();
            }),
          ),
          const SizedBox(height: 12),
          if (_joiningExisting && _knownDindis.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _knownDindis
                  .map((name) => ChoiceChip(
                        label: Text(name),
                        selected: _nameController.text == name,
                        onSelected: (_) => setState(() => _nameController.text = name),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: _joiningExisting ? 'Dindi name (or type one not listed above)' : 'Name your new Dindi',
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}), // refresh the live code preview below
          ),
          if (_nameController.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.tag, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Dindi code: ${dindiTagFor(_nameController.text)} — say this aloud to confirm you\'re both in the same Dindi',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _nameController.text.trim().isEmpty ? null : _save,
            child: Text(_joiningExisting ? 'Join' : 'Create'),
          ),
        ],
      ),
    );
  }
}
