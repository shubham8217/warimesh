// WariMesh — bottom-nav shell hosting the three main screens. Owns the
// single MeshService instance and rebuilds when it changes.
import 'package:flutter/material.dart';

import '../llm_service.dart';
import '../mesh_service.dart';
import '../models.dart';
import 'assistant_screen.dart';
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
  late final LlmService llm = LlmService(mesh: mesh, volunteerName: widget.volunteer.name);
  int _tab = 0;

  // Built once in initState — NOT inside build(). The shell rebuilds on
  // every mesh notification (cooldown ticker, scan state…); recreating the
  // screens each time would reset every screen's State (including the
  // assistant composer's typed text).
  late final List<Widget> _screens = [
    HomeScreen(
      mesh: mesh,
      volunteer: widget.volunteer,
      onLogout: widget.onLogout,
      onOpenSos: () => setState(() => _tab = 1),
      onOpenMissing: () => setState(() => _tab = 2),
    ),
    SosScreen(mesh: mesh),
    MissingScreen(mesh: mesh),
    AssistantScreen(llm: llm),
  ];

  @override
  void initState() {
    super.initState();
    mesh.bootstrap();
  }

  @override
  void dispose() {
    mesh.dispose();
    llm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: mesh,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(child: IndexedStack(index: _tab, children: _screens)),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.sos_outlined), selectedIcon: Icon(Icons.sos), label: 'SOS'),
              NavigationDestination(icon: Icon(Icons.person_search_outlined), selectedIcon: Icon(Icons.person_search), label: 'Missing'),
              NavigationDestination(icon: Icon(Icons.psychology_alt_outlined), selectedIcon: Icon(Icons.psychology_alt), label: 'Assistant'),
            ],
          ),
        );
      },
    );
  }
}
