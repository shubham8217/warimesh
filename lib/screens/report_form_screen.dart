// WariMesh — add a missing-person report. Kept deliberately simple (text +
// icon avatar, no camera/gallery plugin) so it stays reliable to run and
// build tonight — the ask was "share a little description of him", and a
// name + description + last-seen location covers that without adding new
// native dependencies this close to filming.
import 'package:flutter/material.dart';

import '../database_service.dart';
import '../mesh_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class ReportFormScreen extends StatefulWidget {
  final MeshService mesh;
  const ReportFormScreen({super.key, required this.mesh});

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _contact = TextEditingController();
  int _iconIndex = 0;
  int _colorIndex = 0;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _description.dispose();
    _location.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _save({required bool broadcast}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final report = LostReport(
      name: _name.text.trim(),
      age: _age.text.trim(),
      description: _description.text.trim(),
      lastSeenLocation: _location.text.trim(),
      contactInfo: _contact.text.trim(),
      avatarIconIndex: _iconIndex,
      avatarColorIndex: _colorIndex,
      createdAt: DateTime.now(),
    );

    try {
      final id = await LostReportsDb.insert(report);

      if (broadcast) {
        // Name and age ride along on a detail packet so receiving phones
        // can show who to look for — see LostPersonDetailPacket.
        final packet = await widget.mesh.sendAlert(
          kCategoryLostPerson,
          lostName: report.name,
          lostAge: report.age,
        );
        if (packet != null) {
          await LostReportsDb.setBroadcast(id, packet.msgId, DateTime.now());
        }
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save report: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report someone missing')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Center(
              child: LostPersonAvatar(iconIndex: _iconIndex, colorIndex: _colorIndex, radius: 40),
            ),
            const SizedBox(height: 16),
            _AvatarPicker(
              iconIndex: _iconIndex,
              colorIndex: _colorIndex,
              onIconChanged: (i) => setState(() => _iconIndex = i),
              onColorChanged: (i) => setState(() => _colorIndex = i),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.badge_outlined)),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _age,
              decoration: const InputDecoration(labelText: 'Age (e.g. "7" or "approx. 60s")', prefixIcon: Icon(Icons.cake_outlined)),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Appearance, clothing, anything distinctive…',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              maxLines: 3,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'A short description helps people recognize them' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(labelText: 'Last seen location', prefixIcon: Icon(Icons.place_outlined)),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contact,
              decoration: const InputDecoration(labelText: 'Contact info (optional)', prefixIcon: Icon(Icons.call_outlined)),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 8),
            Card(
              color: AppColors.lostPerson.withValues(alpha: 0.08),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: AppColors.lostPerson),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This description stays on your phone. Broadcasting sends a small "look out for this person" beacon to nearby phones over Bluetooth — no internet needed.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.lostPerson),
              onPressed: _saving ? null : () => _save(broadcast: true),
              icon: const Icon(Icons.podcasts),
              label: const Text('Save & broadcast alert'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _saving ? null : () => _save(broadcast: false),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save without broadcasting'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  final int iconIndex;
  final int colorIndex;
  final ValueChanged<int> onIconChanged;
  final ValueChanged<int> onColorChanged;

  const _AvatarPicker({
    required this.iconIndex,
    required this.colorIndex,
    required this.onIconChanged,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: AvatarPalette.icons.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final selected = i == iconIndex;
              return GestureDetector(
                onTap: () => onIconChanged(i),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: selected ? avatarColorFor(colorIndex) : Colors.grey.shade200,
                  child: Icon(avatarIconFor(i), color: selected ? Colors.white : Colors.grey.shade600),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: AvatarPalette.colors.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final selected = i == colorIndex;
              return GestureDetector(
                onTap: () => onColorChanged(i),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: avatarColorFor(i),
                  child: selected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
