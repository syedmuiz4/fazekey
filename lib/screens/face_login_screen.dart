import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../models/area.dart';
import '../models/system_settings.dart';
import '../providers/area_provider.dart';
import '../providers/alert_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/face_provider.dart';
import '../providers/log_provider.dart';
import '../services/firebase_service.dart';
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
  final _firebase = FirebaseService();
  CameraController? _controller;
  FaceProvider? _faceProvider;
  String? _error;
  bool _busy = false;
  bool _recognitionInFlight = false;
  bool _disposeRequestedDuringRecognition = false;
  bool _cameraReleaseStarted = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _faceProvider ??= context.read<FaceProvider>();
  }

  Future<void> _initCamera() async {
    try {
      _cameraReleaseStarted = false;
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

  Future<void> _scan(SystemSettings system) async {
    if (_busy) return;
    setState(() => _busy = true);
    final faceProvider = context.read<FaceProvider>();
    final logProvider = context.read<LogProvider>();
    final alertProvider = context.read<AlertProvider>();
    final authProvider = context.read<AuthProvider>();
    final scanArea = _scanArea(context.read<AreaProvider>().areas);

    try {
      if (system.globalLockdown) {
        await _denyAccess(
          faceProvider: faceProvider,
          logProvider: logProvider,
          alertProvider: alertProvider,
          scanArea: scanArea,
          system: system,
          reason: 'Global lockdown is active',
          alertTitle: 'Access Lockdown',
          alertBody: 'Global lockdown denied an access attempt.',
          snackBarText: 'Intrusion alert: global lockdown denied access.',
        );
        return;
      }

      final controller = _controller;
      if (controller == null ||
          !controller.value.isInitialized ||
          controller.value.isTakingPicture) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      final file = await controller.takePicture();
      final snapshotPath = file.path;

      _recognitionInFlight = true;
      final user = await faceProvider.identify(file);
      final timingDenied = system.shouldDenyScanForRole(
        user?.role,
        DateTime.now(),
      );
      final areaAllowed =
          user != null && (scanArea == null || user.canAccessArea(scanArea));
      final hasAccess = user != null && !timingDenied && areaAllowed;
      if (hasAccess) {
        authProvider.completeFaceLogin(user);
      }
      final reason = user == null
          ? faceProvider.error
          : hasAccess
          ? 'Face verified for ${scanArea?.name ?? 'Campus Gate'}'
          : timingDenied
          ? 'Access denied outside the active access window'
          : 'Access permission is not assigned for ${scanArea?.name ?? 'this area'}';
      final log = faceProvider.buildLog(
        user: user,
        area: scanArea,
        status: hasAccess ? 'granted' : 'denied',
        reason: reason,
        snapshotPath: hasAccess ? null : snapshotPath,
      );
      await logProvider.record(
        log,
        firestoreLogging: system.monitoringWindowLogging,
      );
      if (!hasAccess && system.intrusionAlerts && mounted) {
        await alertProvider.raiseIntrusionAlert(
          title: 'Access Denied',
          body: reason ?? 'An access attempt was denied.',
          severity: user == null ? 'High' : 'Medium',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Intrusion alert: access denied.')),
        );
      }
      await _releaseCameraForDashboardHandoff();
      if (!mounted) return;
      _replaceWithAccessResult(
        user: hasAccess ? user : null,
        log: log,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
        await _initCamera();
      }
    } finally {
      _recognitionInFlight = false;
      if (_disposeRequestedDuringRecognition) {
        await _disposeCamera();
        unawaited(_faceProvider?.closeDetector());
      }
    }
  }

  Future<void> _denyAccess({
    required FaceProvider faceProvider,
    required LogProvider logProvider,
    required AlertProvider alertProvider,
    required Area? scanArea,
    required SystemSettings system,
    required String reason,
    required String alertTitle,
    required String alertBody,
    required String snackBarText,
  }) async {
    final log = faceProvider.buildLog(
      user: null,
      area: scanArea,
      status: 'denied',
      reason: reason,
    );
    await logProvider.record(
      log,
      firestoreLogging: system.monitoringWindowLogging,
    );
    if (system.intrusionAlerts && mounted) {
      await alertProvider.raiseIntrusionAlert(
        title: alertTitle,
        body: alertBody,
        severity: 'Critical',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(snackBarText)));
    }
    if (!mounted) return;
    await _releaseCameraForDashboardHandoff();
    if (!mounted) return;
    _replaceWithAccessResult(user: null, log: log);
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

  Future<void> _releaseCameraForDashboardHandoff() async {
    if (_cameraReleaseStarted) return;
    _cameraReleaseStarted = true;
    await _disposeCamera();
    await SchedulerBinding.instance.endOfFrame;
  }

  void _replaceWithAccessResult({
    required Object? user,
    required Object? log,
  }) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AccessResultScreen.route,
        arguments: {'user': user, 'log': log},
      );
    });
  }

  @override
  void dispose() {
    if (_recognitionInFlight) {
      _disposeRequestedDuringRecognition = true;
      super.dispose();
      return;
    }
    final controller = _controller;
    _controller = null;
    unawaited(controller?.dispose());
    unawaited(_faceProvider?.closeDetector());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final face = context.watch<FaceProvider>();
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: StreamBuilder<SystemSettings>(
            stream: _firebase.watchSystemSettings(),
            initialData: SystemSettings.defaults(),
            builder: (context, snapshot) {
              final settings = snapshot.data ?? SystemSettings.defaults();
              final lockedOut = settings.globalLockdown;
              final timingLocked = settings.shouldDenyScanAt(DateTime.now());
            return Stack(
              children: [
                Positioned.fill(
                  child: _controller?.value.isInitialized == true
                      ? CameraPreview(_controller!)
                      : const Center(child: CircularProgressIndicator()),
                ),
                const Positioned.fill(child: FaceGuideOverlay()),
                if (lockedOut)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: .72),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.lock_clock_rounded,
                                color: Colors.white,
                                size: 56,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                settings.globalLockdown
                                    ? 'Access Lockdown Active'
                                    : 'Access Window Closed',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
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
                          'Face Access',
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
                      if (!lockedOut && timingLocked) ...[
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .56),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Text(
                              'Access window is closed. Admin verification remains available.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_error != null || face.error != null)
                        Text(
                          _error ?? face.error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      const SizedBox(height: 12),
                      PrimaryButton(
                        label: lockedOut ? 'Access Denied' : 'Scan Face',
                        loading: _busy || face.loading,
                        icon: lockedOut
                            ? Icons.lock_clock_rounded
                            : Icons.center_focus_strong_rounded,
                        onPressed: lockedOut ? null : () => _scan(settings),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
