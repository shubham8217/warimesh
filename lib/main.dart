// WariMesh — offline BLE-mesh SOS & Lost Person alert app.
//
// See models.dart for the wire protocol and the honesty note on what can
// and can't travel over the mesh. See mesh_service.dart for the real BLE
// path and Demo Mode (a filming aid for devices/emulators without BLE
// peripheral support).
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'screens/root_shell.dart';
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
      home: const RootShell(),
    );
  }
}
