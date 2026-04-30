import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/area.dart';
import '../providers/area_provider.dart';
import '../providers/face_provider.dart';
import '../providers/log_provider.dart';
import '../providers/system_provider.dart';
import '../widgets/face_overlay.dart';
import '../widgets/primary_button.dart';
import 'access_result_screen.dart';

class FaceLoginScreen extends StatefulWidget {
  const FaceLoginScreen({super.key});
  static const route = '/face-login';

  @override
  State<FaceLoginScreen> createState() => _FaceLoginScreenState();
}

class _FaceLoginScreenState extends State<FaceLoginScreen> {
  CameraController? _controller;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _scan() async {
    final controller = _controller;
    if (_busy ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }
    setState(() => _busy = true);
    final faceProvider = context.read<FaceProvider>();
    final logProvider = context.read<LogProvider>();
    final system = context.read<SystemProvider>().settings;
    final scanArea = _scanArea(context.read<AreaProvider>().areas);
    try {
      final file = await controller.takePicture();
      await _disposeCamera();
      final snapshotPath = file.path;
      if (system.globalLockdown) {
        final log = faceProvider.buildLog(
          user: null,
          area: scanArea,
          status: 'denied',
          reason: 'Global lockdown is active',
          snapshotPath: snapshotPath,
        );
        await logProvider.record(log);
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, AccessResultScreen.route, arguments: {'user': null, 'log': log});
        return;
      }

      final live = await faceProvider.validateLiveness(file);
      if (!live) {
        final log = faceProvider.buildLog(
          user: null,
          area: scanArea,
          status: 'denied',
          reason: faceProvider.error ?? 'Liveness check failed',
          snapshotPath: snapshotPath,
        );
        await logProvider.record(log);
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, AccessResultScreen.route, arguments: {'user': null, 'log': log});
        return;
      }

      final user = await faceProvider.identify(file);
      final hasAccess = user != null && (scanArea == null || user.canAccessArea(scanArea));
      final reason = user == null
          ? faceProvider.error
          : hasAccess
              ? 'Face verified for ${scanArea?.name ?? 'Campus Gate'}'
              : 'RBAC denied: ${user.role} cannot access ${scanArea?.name ?? 'this area'}';
      final log = faceProvider.buildLog(
        user: user,
        area: scanArea,
        status: hasAccess ? 'granted' : 'denied',
        reason: reason,
        snapshotPath: hasAccess ? null : snapshotPath,
      );
      await logProvider.record(log);
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AccessResultScreen.route,
        arguments: {'user': hasAccess ? user : null, 'log': log},
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
        await _initCamera();
      }
    }
  }

  Area? _scanArea(List<Area> areas) {
    if (areas.isEmpty) return null;
    final active = areas.where((a) => a.active).toList();
    if (active.isEmpty) return areas.first;
    for (final area in active) {
      if (area.name.toLowerCase() == 'server room') return area;
    }
    for (final area in active) {
      if (area.name.toLowerCase() == 'it room') return area;
    }
    return active.first;
  }

  Future<void> _disposeCamera() async {
    final controller = _controller;
    _controller = null;
    if (mounted) setState(() {});
    await controller?.dispose();
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final face = context.watch<FaceProvider>();
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _controller?.value.isInitialized == true
                  ? CameraPreview(_controller!)
                  : const Center(child: CircularProgressIndicator()),
            ),
            const Positioned.fill(child: FaceGuideOverlay()),
            Positioned(
              left: 20,
              right: 20,
              top: 16,
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Face Login',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 24,
              child: Column(
                children: [
                  if (_error != null || face.error != null)
                    Text(
                      _error ?? face.error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: 'Scan Face',
                    loading: _busy || face.loading,
                    icon: Icons.center_focus_strong_rounded,
                    onPressed: _scan,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
