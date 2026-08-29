// WariMesh — bottom-nav shell hosting the three main screens. Owns the
// single MeshService instance and rebuilds when it changes.
import 'package:flutter/material.dart';

import '../mesh_service.dart';
import '../models.dart';
import 'alert_overlay.dart';
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

  @override
  void initState() {
    super.initState();
    mesh.bootstrap(widget.volunteer);
    mesh.loadMessages();
  }

  @override
  void dispose() {
    mesh.dispose();
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
      builder: (context, _) {
        final screens = [
          HomeScreen(
            mesh: mesh,
            volunteer: widget.volunteer,
            onLogout: widget.onLogout,
            onOpenSos: () => setState(() => _tab = 1),
            onOpenMissing: () => setState(() => _tab = 2),
          ),
          SosScreen(mesh: mesh),
          MissingScreen(mesh: mesh),
          ChatScreen(mesh: mesh, profile: widget.volunteer),
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
            ],
          ),
        );
      },
    );
  }
}
