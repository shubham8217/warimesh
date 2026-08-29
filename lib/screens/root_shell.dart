// WariMesh — bottom-nav shell hosting the volunteer's screens. Owns the
// single MeshService instance (and the on-device LlmService) and rebuilds
// when the mesh changes.
import 'package:flutter/material.dart';

import '../database_service.dart';
import '../llm_service.dart';
import '../mesh_service.dart';
import '../models.dart';
import 'alert_overlay.dart';
import 'assistant_screen.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'missing_screen.dart';
import 'sos_screen.dart';

class RootShell extends StatefulWidget {
  final UserProfile volunteer;
  final VoidCallback onLogout;
  const RootShell({super.key, required this.volunteer, required this.onLogout});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  final MeshService mesh = MeshService();
  int _tab = 0;
  late UserProfile _profile = widget.volunteer;

  // The assistant is given the live mesh so its system prompt can describe
  // what this phone actually knows. Inference is entirely on-device (see
  // llm_service.dart) — the only kind that makes sense in an app whose
  // premise is having no network.
  late final LlmService llm = LlmService(mesh: mesh, volunteerName: widget.volunteer.name);

  @override
  void initState() {
    super.initState();
    mesh.bootstrap(widget.volunteer);
    mesh.loadMessages();
    llm.init();
  }

  /// Persists a newly created or joined Dindi and updates the mesh's live
  /// notification-tier tag. The volunteer home had no Dindi card at all
  /// before, so this path simply didn't exist for a volunteer — they were
  /// stuck with whatever camp ID they typed at sign-in.
  Future<void> _setDindi(String name) async {
    final updated = UserProfile(
      name: _profile.name,
      phone: _profile.phone,
      role: _profile.role,
      groupOrId: name,
      meshId: _profile.meshId,
      loggedInAt: _profile.loggedInAt,
    );
    try {
      await UserDb.save(updated);
    } catch (_) {
      // Non-fatal — apply it for this session even if it couldn't be
      // persisted, rather than silently ignoring the choice.
    }
    mesh.updateDindi(name);
    // The chat thread is per-Dindi, so switching group must reload it.
    await mesh.loadMessages();
    if (mounted) setState(() => _profile = updated);
  }

  @override
  void dispose() {
    mesh.dispose();
    llm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MeshAlertHost(
      mesh: mesh,
      child: _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    return AnimatedBuilder(
      animation: mesh,
      // The screen list is built INSIDE this callback, not once outside it
      // — mesh.notifyListeners() (e.g. Bluetooth turning on) only re-runs
      // this builder, not the outer State.build(). Building the list here
      // means each mesh update produces fresh widget instances that Flutter
      // will actually rebuild, instead of reusing identical widget objects
      // it can skip. That's why "Not connected" used to only update after
      // switching tabs (which does trigger the outer build via setState).
      //
      // New widget instances do NOT reset the screens' State: Flutter keeps
      // State by runtime type and position, so the assistant's and chat's
      // typed-but-unsent text survives every mesh notification.
      builder: (context, _) {
        final screens = [
          HomeScreen(
            mesh: mesh,
            volunteer: _profile,
            onLogout: widget.onLogout,
            onOpenSos: () => setState(() => _tab = 1),
            onOpenMissing: () => setState(() => _tab = 2),
            onDindiChanged: _setDindi,
          ),
          SosScreen(mesh: mesh),
          MissingScreen(mesh: mesh),
          ChatScreen(mesh: mesh, profile: _profile),
          AssistantScreen(llm: llm),
        ];
        return Scaffold(
          body: SafeArea(child: IndexedStack(index: _tab, children: screens)),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
              const NavigationDestination(icon: Icon(Icons.sos_outlined), selectedIcon: Icon(Icons.sos), label: 'SOS'),
              const NavigationDestination(icon: Icon(Icons.person_search_outlined), selectedIcon: Icon(Icons.person_search), label: 'Missing'),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: mesh.unreadMessages > 0,
                  label: Text('${mesh.unreadMessages}'),
                  child: const Icon(Icons.forum_outlined),
                ),
                selectedIcon: const Icon(Icons.forum),
                label: 'Chat',
              ),
              const NavigationDestination(
                icon: Icon(Icons.psychology_alt_outlined),
                selectedIcon: Icon(Icons.psychology_alt),
                label: 'Assistant',
              ),
            ],
          ),
        );
      },
    );
  }
}
