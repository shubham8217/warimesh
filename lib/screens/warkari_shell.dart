// WariMesh — bottom-nav shell for a signed-in warkari (pilgrim). Mirrors
// root_shell.dart (the volunteer shell) but swaps the volunteer dashboard
// for the trimmed-down WarkariHomeScreen; SOS, Missing, Chat and the
// on-device Assistant are the same screens either role uses.
import 'package:flutter/material.dart';

import '../database_service.dart';
import '../llm_service.dart';
import '../mesh_service.dart';
import '../models.dart';
import 'alert_overlay.dart';
import 'assistant_screen.dart';
import 'chat_screen.dart';
import 'missing_screen.dart';
import 'sos_screen.dart';
import 'warkari_home_screen.dart';

class WarkariShell extends StatefulWidget {
  final UserProfile warkari;
  final VoidCallback onLogout;
  const WarkariShell({super.key, required this.warkari, required this.onLogout});

  @override
  State<WarkariShell> createState() => _WarkariShellState();
}

class _WarkariShellState extends State<WarkariShell> {
  final MeshService mesh = MeshService();
  int _tab = 0;
  late UserProfile _profile = widget.warkari;

  // The assistant is given the live mesh so its system prompt can describe
  // what this phone actually knows — nearby Dindi members, active alerts,
  // missing-person reports. Inference is entirely on-device (see
  // llm_service.dart), which is the only kind that makes sense in an app
  // whose premise is having no network.
  late final LlmService llm = LlmService(mesh: mesh, volunteerName: widget.warkari.name);

  @override
  void initState() {
    super.initState();
    mesh.bootstrap(widget.warkari);
    mesh.loadMessages();
    llm.init();
  }

  /// Called from WarkariHomeScreen after the Dindi picker sheet returns a
  /// chosen name — persists it, updates the mesh's live notification-tier
  /// tag, and rebuilds so the Home screen reflects the new Dindi
  /// immediately without needing to sign out and back in.
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
      // Non-fatal — still apply it for this session even if it couldn't be
      // persisted, rather than silently ignoring the person's choice.
    }
    mesh.updateDindi(name);
    // The thread is per-Dindi, so switching group must reload it rather
    // than leave the previous Dindi's conversation on screen.
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
          WarkariHomeScreen(
            mesh: mesh,
            warkari: _profile,
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
