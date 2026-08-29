// WariMesh — offline BLE-mesh SOS & Lost Person alert app.
//
// See models.dart for the wire protocol and the honesty note on what can
// and can't travel over the mesh. See mesh_service.dart for the real BLE
// path and Demo Mode (a filming aid for devices/emulators without BLE
// peripheral support).
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'database_service.dart';
import 'models.dart';
import 'screens/login_screen.dart';
import 'screens/role_select_screen.dart';
import 'screens/root_shell.dart';
import 'screens/warkari_shell.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  runApp(const WariMeshApp());
}

class WariMeshApp extends StatelessWidget {
  const WariMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WariMesh',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AuthGate(),
    );
  }
}

/// Decides, on launch, whether this phone already has a signed-in person
/// (see database_service.dart's volunteer_profile table) or needs to sign
/// in first: pick a role on [RoleSelectScreen], then [LoginScreen]. Once
/// signed in, a warkari and a volunteer land on different shells — see
/// [WarkariShell] and [RootShell]. Kept out of those shells so the mesh
/// service (BLE, permissions, foreground task) only ever bootstraps once
/// someone is actually signed in.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  UserProfile? _profile;
  UserRole? _pendingRole;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await UserDb.current();
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      // Local DB unavailable — fall through to role selection rather than
      // getting stuck on a spinner.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await UserDb.clear();
    if (mounted) setState(() => _profile = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final profile = _profile;
    if (profile != null) {
      return profile.role == UserRole.volunteer
          ? RootShell(volunteer: profile, onLogout: _logout)
          : WarkariShell(warkari: profile, onLogout: _logout);
    }

    final role = _pendingRole;
    if (role == null) {
      return RoleSelectScreen(onRoleChosen: (r) => setState(() => _pendingRole = r));
    }
    return LoginScreen(
      role: role,
      onBack: () => setState(() => _pendingRole = null),
      onLoggedIn: (profile) => setState(() => _profile = profile),
    );
  }
}
