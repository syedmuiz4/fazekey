import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import '../providers/face_provider.dart';
import '../widgets/face_overlay.dart';
import '../widgets/primary_button.dart';
import 'dashboard_screen.dart';

class FaceRegistrationScreen extends StatefulWidget {
  const FaceRegistrationScreen({super.key});
  static const route = '/face-registration';

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class FaceRegistrationArgs {
  const FaceRegistrationArgs({required this.user});

  final AppUser user;
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  CameraController? _controller;
  FaceProvider? _faceProvider;
  final _captures = <XFile>[];
  String? _error;
  bool _busy = false;
  bool _modelReady = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
    unawaited(_prepareFaceModel());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _faceProvider ??= context.read<FaceProvider>();
  }

  Future<void> _prepareFaceModel() async {
    final ready = await context.read<FaceProvider>().ensureModelReady();
    if (mounted) {
      setState(() => _modelReady = ready);
    }
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

  Future<void> _capture() async {
    final controller = _controller;
    if (_busy ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }
    setState(() => _busy = true);
    try {
      final file = await controller.takePicture();
      if (mounted) {
        setState(() {
          _captures.add(file);
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  Future<void> _disposeCamera() async {
    final controller = _controller;
    _controller = null;
    if (mounted) setState(() {});
    await controller?.dispose();
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    unawaited(controller?.dispose());
    unawaited(_faceProvider?.closeDetector());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final face = context.watch<FaceProvider>();
    final auth = context.watch<AuthProvider>();
    final args = ModalRoute.of(context)?.settings.arguments;
    final selectedUser = args is FaceRegistrationArgs ? args.user : null;
    if (selectedUser != null && auth.loading && auth.user == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (selectedUser != null && !auth.isAdmin) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Text(
              'Management access is unavailable.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      );
    }
    final user = selectedUser ?? auth.user;
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
                  Expanded(
                    child: Text(
                      'Face Enrollment ${_captures.length}/3',
                      style: const TextStyle(
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
                    label: _captures.length < 3
                        ? 'Capture Sample'
                        : 'Save Biometric Profile',
                    loading: _busy || face.loading,
                    icon: _captures.length < 3
                        ? Icons.camera_alt_rounded
                        : Icons.check_circle_rounded,
                    onPressed: () async {
                      if (_captures.length < 3) {
                        await _capture();
                        return;
                      }
                      if (user == null) return;
                      final faceProvider = context.read<FaceProvider>();
                      final authProvider = context.read<AuthProvider>();
                      final modelReady =
                          _modelReady || await faceProvider.ensureModelReady();
                      if (!modelReady) {
                        if (mounted) setState(() => _modelReady = false);
                        return;
                      }
                      if (!mounted) return;
                      setState(() => _busy = true);
                      await _disposeCamera();
                      final ok = await faceProvider.registerFace(
                        user,
                        _captures,
                      );
                      await authProvider.refreshProfile();
                      if (ok && mounted) {
                        SchedulerBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          final navigator = Navigator.of(context);
                          if (selectedUser == null) {
                            navigator.pushReplacementNamed(
                              DashboardScreen.route,
                            );
                          } else {
                            navigator.pop(true);
                          }
                        });
                      }
                      if (!ok && mounted) {
                        setState(() => _busy = false);
                        await _initCamera();
                      }
                    },
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
