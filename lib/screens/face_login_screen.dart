import 'dart:async';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../models/access_log.dart';
import '../models/area.dart';
import '../models/system_settings.dart';
import '../providers/area_provider.dart';
import '../providers/alert_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/face_provider.dart';
import '../providers/log_provider.dart';
import '../providers/system_provider.dart';
import '../services/firebase_service.dart';
import '../widgets/face_overlay.dart';
import '../widgets/primary_button.dart';
import 'access_result_screen.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';

class FaceLoginScreen extends StatefulWidget {
  const FaceLoginScreen({super.key});
  static const route = '/face-login';

  @override
  State<FaceLoginScreen> createState() => _FaceLoginScreenState();
}

class _FaceLoginScreenState extends State<FaceLoginScreen> {
  static const _serverRoomName = 'Server Room';
  static const _itLabName = 'IT Lab';

  CameraController? _controller;
  FaceProvider? _faceProvider;
  String? _error;
  bool _busy = false;
  bool _isProcessing = false;
  bool isNavigating = false;
  bool _recognitionInFlight = false;
  bool _disposeRequestedDuringRecognition = false;
  bool _cameraReleaseStarted = false;
  StreamSubscription<void>? _imageStreamSubscription;

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
      _setStateAfterFrame(() {});
    } catch (e) {
      if (mounted) _setStateAfterFrame(() => _error = e.toString());
    }
  }

  Future<void> _scan(SystemSettings system) async {
    if (_isProcessing || isNavigating) return;
    final scanArea = _activeAreaFromProvider();
    _isProcessing = true;
    _setStateAfterFrame(() {
      _busy = true;
      _error = null;
    });
    final faceProvider = context.read<FaceProvider>();
    final logProvider = context.read<LogProvider>();
    final alertProvider = context.read<AlertProvider>();
    final authProvider = context.read<AuthProvider>();
    final firebase = context.read<FirebaseService>();
    AccessLog? pendingResultLog;

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
        _isProcessing = false;
        if (mounted) _setStateAfterFrame(() => _busy = false);
        return;
      }

      final file = await controller.takePicture();
      final snapshotPath = file.path;

      _recognitionInFlight = true;
      final user = await faceProvider.identify(file);
      _isProcessing = true;
      await _releaseCameraForNavigation();
      final adminOverride = user?.hasAdminOverride == true;
      final grantEvaluation = user == null
          ? null
          : await firebase.evaluateAccessGrant(
              user: user,
              area: scanArea,
              moment: DateTime.now(),
            );
      final verifiedArea = grantEvaluation?.granted == true ? scanArea : null;
      final accessArea = adminOverride ? scanArea : verifiedArea ?? scanArea;
      final adminApproved = user != null && (adminOverride || user.isApproved);
      final timingDenied = system.shouldDenyScanForRole(
        user?.role,
        DateTime.now(),
      );
      final registeredForScanner =
          user != null && user.isRegisteredForArea(scanArea);
      final areaAllowed =
          user != null &&
          (adminOverride ||
              (verifiedArea != null &&
                  registeredForScanner &&
                  user.canAccessRegisteredArea(scanArea)));
      final hasAccess =
          user != null && adminApproved && !timingDenied && areaAllowed;
      if (hasAccess) {
        authProvider.completeFaceLogin(user);
      }
      final matchedUid = faceProvider.lastMatchedUserId;
      final reason = user == null
          ? matchedUid == null
                ? (faceProvider.error ?? 'Unknown face')
                : 'Biometric UID $matchedUid was not found in Firestore users collection.'
          : hasAccess
          ? adminOverride
                ? 'Admin override verified for ${_areaName(accessArea)}'
                : 'Face Identity verified for ${_areaName(verifiedArea)}'
          : !adminApproved
          ? 'Verification Required by Admin'
          : timingDenied
          ? 'Access denied outside the active access window'
          : grantEvaluation?.expired == true
          ? 'Access Expired'
          : !registeredForScanner
          ? 'Unauthorized zone: ${user.name} is not assigned to scanner room ${_areaName(scanArea)}'
          : verifiedArea == null
          ? grantEvaluation?.pending == true
                ? 'Access window starts ${_formatGrantDate(grantEvaluation!.grant!.startAt)}'
                : 'No active temporal access window for scanner room ${_areaName(scanArea)}'
          : 'RBAC denied: ${user.roleLabel} is not authorized for scanner room ${_areaName(scanArea)}';
      final log = faceProvider.buildLog(
        user: user,
        area: accessArea,
        areaName: _areaName(accessArea),
        status: hasAccess
            ? 'granted'
            : grantEvaluation?.expired == true
            ? 'expired'
            : 'denied',
        reason: reason,
        snapshotPath: hasAccess ? null : snapshotPath,
      );
      pendingResultLog = log;
      await logProvider.record(
        log,
        firestoreLogging: system.monitoringWindowLogging,
      );
      if (!hasAccess && system.intrusionAlerts && mounted) {
        await alertProvider.raiseIntrusionAlert(
          title: 'Access Denied',
          body: reason,
          severity: user == null ? 'High' : 'Medium',
        );
        if (!mounted) return;
        if (!isNavigating) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Intrusion alert: access denied.')),
          );
        }
      }
      if (!mounted) return;
      _replaceWithAccessResult(user: hasAccess ? user : null, log: log);
    } catch (e) {
      _isProcessing = true;
      await _releaseCameraForNavigation();
      if (_isFirestorePermissionDenied(e)) {
        await _handleFirestorePermissionDenied(pendingResultLog, scanArea);
        return;
      }
      if (mounted) {
        _setStateAfterFrame(() {
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
      if (!isNavigating) {
        _isProcessing = false;
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
    if (isNavigating) return;
    _isProcessing = true;
    await _releaseCameraForNavigation();
    final log = faceProvider.buildLog(
      user: null,
      area: scanArea,
      areaName: _areaName(scanArea),
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
      if (!isNavigating) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(snackBarText)));
      }
    }
    if (!mounted) return;
    _replaceWithAccessResult(user: null, log: log);
  }

  Area _activeAreaFromProvider() {
    final areas = context.read<AreaProvider>().areas;
    final active = areas.where((area) => area.active).toList();
    final scannerRoomId = _scannerRoomIdFromRoute();
    if (scannerRoomId != null) {
      for (final area in active) {
        if (area.id == scannerRoomId ||
            _triNormalize(area.roomNumber) == _triNormalize(scannerRoomId) ||
            _triNormalize(_areaName(area)) == _triNormalize(scannerRoomId)) {
          return area;
        }
      }
    }
    for (final area in active) {
      if (_isRecognizedScannerRoom(area, _serverRoomName)) return area;
    }
    for (final area in active) {
      if (_isRecognizedScannerRoom(area, _itLabName)) return area;
    }
    return active.isEmpty ? _fallbackServerRoom() : active.first;
  }

  String? _scannerRoomIdFromRoute() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String && args.trim().isNotEmpty) return args.trim();
    if (args is Map<String, dynamic>) {
      final value = args['roomId'] ?? args['areaId'] ?? args['scannerRoomId'];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return null;
  }

  String _triNormalize(String value) =>
      value.trim().toLowerCase().replaceAll(' ', '');

  bool _isRecognizedScannerRoom(Area area, String roomName) =>
      _triNormalize(_areaName(area)) == _triNormalize(roomName);

  String _formatGrantDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Area _fallbackServerRoom() => Area(
    id: 'scanner_default_server_room',
    name: _serverRoomName,
    location: 'FAZEKEY',
    floor: '',
    roomNumber: '',
    active: true,
    createdAt: DateTime.now(),
    allowedDepartments: const [],
    allowedRoles: const ['User', 'Admin'],
    currentOccupancy: 0,
    capacity: 0,
  );

  String _areaName(Area? area) {
    if (area == null) return 'No active room configured';
    final name = area.name.trim();
    if (name.isNotEmpty) return name;
    final floor = area.floor.trim();
    final roomNumber = area.roomNumber.trim();
    if (floor.isNotEmpty && roomNumber.isNotEmpty) {
      return '$floor - Room $roomNumber';
    }
    if (roomNumber.isNotEmpty) return 'Room $roomNumber';
    return area.location.trim().isEmpty
        ? 'No active room configured'
        : area.location.trim();
  }

  Future<void> _disposeCamera() async {
    await _cancelImageStreamSubscription();
    final controller = _controller;
    _controller = null;
    if (mounted) _setStateAfterFrame(() {});
    if (controller == null) return;
    await _stopAndDisposeController(controller);
  }

  Future<void> _disposeCameraAfterFirestorePermissionDenied() async {
    await _releaseCameraForNavigation();
  }

  Future<void> _releaseCameraForNavigation() async {
    if (_cameraReleaseStarted) return;
    _cameraReleaseStarted = true;
    _isProcessing = true;
    await _cancelImageStreamSubscription();
    final controller = _controller;
    _controller = null;
    if (controller == null) {
      if (mounted) _setStateAfterFrame(() {});
      return;
    }
    await _stopAndDisposeController(controller);
    if (mounted) _setStateAfterFrame(() {});
    await SchedulerBinding.instance.endOfFrame;
  }

  Future<void> _stopAndDisposeController(CameraController controller) async {
    try {
      if (controller.value.isInitialized &&
          controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Continue disposing; the controller may already be unwinding the stream.
    }
    try {
      await controller.dispose();
    } catch (_) {
      // The platform may already have released this camera instance.
    }
  }

  Future<void> _cancelImageStreamSubscription() async {
    await _imageStreamSubscription?.cancel();
    _imageStreamSubscription = null;
  }

  void _replaceWithAccessResult({required Object? user, required Object? log}) {
    if (isNavigating) return;
    isNavigating = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        AccessResultScreen.route,
        (_) => false,
        arguments: {'user': user, 'log': log},
      );
    });
  }

  Future<void> _handleFirestorePermissionDenied(
    AccessLog? pendingResultLog,
    Area? scanArea,
  ) async {
    await _disposeCameraAfterFirestorePermissionDenied();
    if (!mounted) return;
    final log =
        pendingResultLog ??
        context.read<FaceProvider>().buildLog(
          user: null,
          area: scanArea,
          status: 'denied',
          reason: 'Firestore permission denied while logging access.',
        );
    if (!isNavigating) _setStateAfterFrame(() => _busy = false);
    _replaceWithAccessResult(user: null, log: _permissionDeniedLog(log));
  }

  Future<void> _popAfterCameraRelease() async {
    if (_isProcessing || isNavigating) return;
    _isProcessing = true;
    await _releaseCameraForNavigation();
    if (!mounted) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = context.read<AuthProvider>().hasSignedInAccount
          ? DashboardScreen.route
          : LoginScreen.route;
      Navigator.of(context).pushNamedAndRemoveUntil(target, (_) => false);
    });
  }

  void _setStateAfterFrame(VoidCallback update) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(update);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  bool _isFirestorePermissionDenied(Object error) =>
      (error is FirebaseException &&
          error.plugin == 'cloud_firestore' &&
          error.code == 'permission-denied') ||
      error.toString().toLowerCase().contains(
        'cloud_firestore/permission-denied',
      );

  AccessLog _permissionDeniedLog(AccessLog log) => AccessLog(
    id: log.id,
    userId: log.userId,
    userName: log.userName,
    areaId: log.areaId,
    areaName: log.areaName,
    status: 'denied',
    reason: 'Firestore permission denied while logging access.',
    timestamp: log.timestamp,
    synced: log.synced,
    snapshotPath: log.snapshotPath,
  );

  @override
  void dispose() {
    if (_recognitionInFlight) {
      _disposeRequestedDuringRecognition = true;
      super.dispose();
      return;
    }
    final controller = _controller;
    _controller = null;
    unawaited(_cancelImageStreamSubscription());
    if (controller != null) {
      unawaited(_stopAndDisposeController(controller));
    }
    unawaited(_faceProvider?.closeDetector());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final face = context.watch<FaceProvider>();
    final settings = context.watch<SystemProvider>().settings;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_popAfterCameraRelease());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Builder(
            builder: (context) {
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
                          onPressed: _popAfterCameraRelease,
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
      ),
    );
  }
}
