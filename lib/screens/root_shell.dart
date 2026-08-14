// WariMesh — bottom-nav shell hosting the three main screens. Owns the
// single MeshService instance and rebuilds when it changes.
import 'package:flutter/material.dart';

import '../mesh_service.dart';
import 'home_screen.dart';
import 'missing_screen.dart';
import 'sos_screen.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
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
      HomeScreen(mesh: mesh, onOpenSos: () => setState(() => _tab = 1), onOpenMissing: () => setState(() => _tab = 2)),
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
