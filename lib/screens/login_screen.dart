// WariMesh — sign-in, for whichever role was picked on RoleSelectScreen.
//
// WariMesh has no server and works with no internet connection at all, so
// this deliberately isn't a username/password account check against a
// backend — there's nothing to check against in the field. It's an
// on-device identity card: it asks who is carrying this phone, and saves
// that locally (see UserDb) so mesh activity and reports can be
// attributed to a person, not just a random device label. It only runs
// once per phone — see the AuthGate in main.dart.
//
// A warkari's Dindi is deliberately NOT collected here — it's set (and can
// be changed later) from the Home screen instead, via DindiPicker in
// dindi_picker.dart. Keeps this screen to what's needed before the mesh
// can even start: a name and a phone number.
import 'package:flutter/material.dart';

import '../database_service.dart';
import '../models.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  final UserRole role;
  final ValueChanged<UserProfile> onLoggedIn;
  final VoidCallback onBack;
  const LoginScreen({
    super.key,
    required this.role,
    required this.onLoggedIn,
    required this.onBack,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _groupOrId = TextEditingController(); // volunteer camp/ID field only
  bool _saving = false;

  bool get _isWarkari => widget.role == UserRole.warkari;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _groupOrId.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final profile = UserProfile(
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      role: widget.role,
      // A warkari picks their Dindi later, on the Home screen — starts
      // unset. A volunteer's camp/ID is still collected here.
      groupOrId: _isWarkari
          ? '—'
          : (_groupOrId.text.trim().isEmpty ? '—' : _groupOrId.text.trim()),
      meshId: generateMeshId(widget.role),
      loggedInAt: DateTime.now(),
    );

    try {
      await UserDb.save(profile);
      if (mounted) widget.onLoggedIn(profile);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save your details: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _isWarkari ? AppColors.lostPerson : AppColors.sos;
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Change role',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isWarkari ? Icons.directions_walk : Icons.support_agent,
                    size: 48,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'WariMesh',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.role.label} sign-in',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Your name is required'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  prefixIcon: Icon(Icons.call_outlined),
                ),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'A phone number is required'
                    : null,
              ),
              if (!_isWarkari) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _groupOrId,
                  decoration: const InputDecoration(
                    labelText: 'Volunteer / camp ID (optional)',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
              const SizedBox(height: 12),
              Card(
                color: accent.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 18, color: accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _isWarkari
                              ? 'WariMesh works fully offline. There\'s no account server — your details are saved only on this phone. You\'ll pick or create your Dindi from the Home screen after signing in.'
                              : 'WariMesh works fully offline. There\'s no account server — your details are saved only on this phone, so responders and reports can be traced back to you.',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: accent),
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.login),
                label: Text(_saving ? 'Signing in…' : 'Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
