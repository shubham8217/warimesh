// WariMesh — bottom-nav shell for a signed-in warkari (pilgrim). Mirrors
// root_shell.dart (the volunteer shell) but swaps the volunteer dashboard
// for the trimmed-down WarkariHomeScreen; SOS and Missing are the same
// screens either role uses.
import 'package:flutter/material.dart';

import '../llm_service.dart';
import '../mesh_service.dart';
import '../models.dart';
import 'assistant_screen.dart';
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
  late final LlmService llm = LlmService(mesh: mesh, volunteerName: widget.warkari.name);
  int _tab = 0;

  // Built once in initState — NOT inside build(). The shell rebuilds on
  // every mesh notification; recreating the screens each time would reset
  // every screen's State (including the assistant composer's typed text).
  late final List<Widget> _screens = [
    WarkariHomeScreen(
      mesh: mesh,
      warkari: widget.warkari,
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
