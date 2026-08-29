// WariMesh — bottom-nav shell for a signed-in warkari (pilgrim). Mirrors
// root_shell.dart (the volunteer shell) but swaps the volunteer dashboard
// for the trimmed-down WarkariHomeScreen; SOS and Missing are the same
// screens either role uses.
import 'package:flutter/material.dart';

import '../mesh_service.dart';
import '../models.dart';
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

  @override
  void initState() {
    super.initState();
    mesh.bootstrap();
  }

  @override
  void dispose() {
    mesh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      WarkariHomeScreen(
        mesh: mesh,
        warkari: widget.warkari,
        onLogout: widget.onLogout,
        onOpenSos: () => setState(() => _tab = 1),
        onOpenMissing: () => setState(() => _tab = 2),
      ),
      SosScreen(mesh: mesh),
      MissingScreen(mesh: mesh),
    ];
    return AnimatedBuilder(
      animation: mesh,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(child: IndexedStack(index: _tab, children: screens)),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.sos_outlined), selectedIcon: Icon(Icons.sos), label: 'SOS'),
              NavigationDestination(icon: Icon(Icons.person_search_outlined), selectedIcon: Icon(Icons.person_search), label: 'Missing'),
            ],
          ),
        );
      },
    );
  }
}
