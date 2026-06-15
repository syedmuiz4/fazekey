import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import '../models/access_log.dart';
import '../models/app_user.dart';
import '../models/area.dart';
import '../models/system_settings.dart';
import '../providers/area_provider.dart';
import '../providers/alert_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/face_provider.dart';
import '../providers/log_provider.dart';
import '../providers/system_provider.dart';
import '../services/firebase_service.dart';
import '../widgets/app_background.dart';
import '../widgets/corporate_chrome.dart';
import '../widgets/face_overlay.dart';
import 'access_result_screen.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';
import 'user_dashboard_screen.dart';

class FaceLoginScreen extends StatefulWidget {
  const FaceLoginScreen({super.key});
  static const route = '/face-login';

  @override
  State<FaceLoginScreen> createState() => _FaceLoginScreenState();
}

class _FaceLoginScreenState extends State<FaceLoginScreen> {
  static const _serverRoomName = 'Server Room';
  static const _ictOfficeName = 'ICT Office';
  static const _minimumFrameLuminance = 72.0;

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
    var scanArea = _activeAreaFromProvider();
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
    final sessionAction = _scannerSessionAction();
    final appLoginOnly = _isAppFaceLogin();
    var scanRoomName = _scannerRoomDisplayLabel();
    AccessLog? pendingResultLog;

    try {
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
      final hasSafeLight = await _hasSafeFrameLuminance(snapshotPath);
      if (!hasSafeLight) {
        _setStateAfterFrame(() {
          _error =
              'Lighting is too low for secure face verification. Move to a brighter area and try again.';
          _busy = false;
        });
        return;
      }

      _recognitionInFlight = true;
      final localMatch = await faceProvider.identifyLocalMatch(file);
      _isProcessing = true;
      await _releaseCameraForNavigation();

      final user = await faceProvider.resolveLocalMatch(localMatch);

      if (appLoginOnly) {
        if (user == null || !user.isApproved || !user.hasFace) {
          final log = faceProvider.buildLog(
            user: user,
            area: scanArea,
            areaName: 'Application Face Login',
            status: 'denied',
            reason: user == null
                ? 'Face not recognized'
                : !user.hasFace
                ? 'Face profile is not enrolled'
                : 'Account needs admin review',
            snapshotPath: snapshotPath,
          );
          pendingResultLog = log;
          await logProvider.record(
            log,
            firestoreLogging: system.monitoringWindowLogging,
          );
          if (!mounted) return;
          _replaceWithAccessResult(user: null, log: log);
          return;
        }
        if (user.isAdmin) {
          final verifiedLog = faceProvider.buildLog(
            user: user,
            area: scanArea,
            areaName: 'Application Face Login',
            status: 'granted',
            reason: 'Administrator face identity verified',
          );
          await logProvider.record(verifiedLog);
          authProvider.completeFaceLogin(user);
          unawaited(
            firebase
                .recordAppLogin(user, method: 'face_biometric')
                .catchError((_) {}),
          );
          if (!mounted) return;
          await _showSuccessAndNavigate(user, log: verifiedLog);
          return;
        }
        final continueToRoomSelection = await _showVerifiedIdentity(user);
        if (!continueToRoomSelection) {
          if (!mounted) return;
          _setStateAfterFrame(() => _busy = false);
          await _initCamera();
          return;
        }
        final selectedArea = await _selectRoomAfterRecognition(firebase);
        if (selectedArea == null) {
          if (!mounted) return;
          _setStateAfterFrame(() => _busy = false);
          await _initCamera();
          return;
        }
        scanArea = selectedArea;
        scanRoomName = _roomSelectionLabel(selectedArea);
      }

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

      if (sessionAction == 'exit') {
        final hasExitIdentity = user != null && user.isApproved && user.hasFace;
        final exitChange = hasExitIdentity
            ? await firebase.recordRoomExit(
                user: user,
                area: scanArea,
                areaName: scanRoomName,
              )
            : null;
        final exitGranted = exitChange?.allowed == true;
        final exitReason = !hasExitIdentity
            ? 'No permission access'
            : exitGranted
            ? 'Exit registered for $scanRoomName'
            : exitChange?.message ?? 'No permission access';
        final log = faceProvider.buildLog(
          user: user,
          area: scanArea,
          areaName: scanRoomName,
          status: exitGranted ? 'granted' : 'locked',
          reason: exitReason,
          snapshotPath: exitGranted ? null : snapshotPath,
        );
        pendingResultLog = log;
        await logProvider.record(
          log,
          firestoreLogging: system.monitoringWindowLogging,
        );
        if (!mounted) return;
        if (exitGranted) {
          await _showSuccessAndNavigate(user!, log: log);
        } else {
          _replaceWithAccessResult(user: null, log: log);
        }
        return;
      }

      final grantEvaluation = user == null
          ? null
          : await firebase.evaluateAccessGrant(
              user: user,
              area: scanArea,
              moment: DateTime.now(),
            );
      final verifiedArea = grantEvaluation?.granted == true ? scanArea : null;
      final accessArea = verifiedArea ?? scanArea;
      final adminApproved = user != null && user.isApproved;
      final faceRegistered = user != null && user.hasFace;
      final timingDenied =
          _hasExplicitTemporalPolicy(system) &&
          system.shouldDenyScanAt(DateTime.now());
      final registeredForScanner =
          user != null &&
          (user.isRegisteredForArea(scanArea) ||
              grantEvaluation?.granted == true);
      final approvedGrantAllowed =
          user != null &&
          grantEvaluation?.granted == true &&
          scanArea.active &&
          !scanArea.revokedUserIds.contains(user.id) &&
          (scanArea.capacity <= 0 ||
              scanArea.currentOccupancy < scanArea.capacity);
      final areaAllowed =
          user != null &&
          verifiedArea != null &&
          registeredForScanner &&
          (approvedGrantAllowed || user.canAccessArea(scanArea));
      final temporalAllowed = !timingDenied;
      var hasAccess =
          user != null &&
          adminApproved &&
          faceRegistered &&
          temporalAllowed &&
          areaAllowed;
      var lockReason = '';
      if (user != null) {
        final activeSession = await firebase.getActiveRoomSession(user.id);
        if (activeSession != null) {
          hasAccess = false;
          lockReason = 'Locked: Current session active elsewhere';
        }
      }
      if (hasAccess) {
        final entryChange = await firebase.recordRoomEntry(
          user: user!,
          area: scanArea,
          areaName: scanRoomName,
        );
        if (!entryChange.allowed) {
          hasAccess = false;
          lockReason = entryChange.message;
        }
      }
      final reason = user == null
          ? 'No permission access'
          : hasAccess
          ? 'Face Identity verified for ${_areaName(verifiedArea)}'
          : lockReason.isNotEmpty
          ? lockReason
          : !adminApproved
          ? 'No permission access'
          : !faceRegistered
          ? 'Face profile is not enrolled'
          : !temporalAllowed
          ? 'No permission access'
          : grantEvaluation?.expired == true
          ? 'No permission access'
          : !registeredForScanner
          ? 'No permission access'
          : verifiedArea == null
          ? 'No permission access'
          : 'No permission access';
      final log = faceProvider.buildLog(
        user: user,
        area: accessArea,
        areaName: _areaName(accessArea),
        status: hasAccess
            ? 'granted'
            : lockReason.isNotEmpty
            ? 'locked'
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
      if (!hasAccess &&
          user != null &&
          adminApproved &&
          faceRegistered &&
          temporalAllowed &&
          lockReason.isEmpty) {
        await firebase.createRoomAccessRequest(
          user: user,
          area: scanArea,
          areaName: scanRoomName,
        );
        if (mounted) {
          unawaited(
            alertProvider.raiseIntrusionAlert(
              title: 'Room Access Request',
              body: '${user.name} requested entry to $scanRoomName.',
              severity: 'Info',
            ),
          );
        }
        authProvider.completeFaceLogin(user);
        unawaited(
          firebase
              .recordAppLogin(user, method: 'face_biometric_pending_room')
              .catchError((_) {}),
        );
        if (!mounted) return;
        _replaceWithAccessResult(
          user: user,
          log: log,
          extraArgs: {'waitingApproval': true, 'requestedRoom': scanRoomName},
        );
        return;
      }
      if (hasAccess) {
        final verifiedUser = user!;
        authProvider.completeFaceLogin(verifiedUser);
        unawaited(
          firebase
              .recordAppLogin(verifiedUser, method: 'face_biometric')
              .catchError((_) {}),
        );
      }
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
      if (hasAccess) {
        await _showSuccessAndNavigate(user!, log: log);
      } else {
        _replaceWithAccessResult(user: null, log: log);
      }
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

  Future<bool> _showVerifiedIdentity(AppUser user) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.verified_user_rounded, color: Color(0xFF16A34A)),
                SizedBox(width: 10),
                Text('Verified'),
              ],
            ),
            content: Text(
              '${user.name.trim().isEmpty ? 'User' : user.name.trim()}\nFace identity verified.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Select Room'),
              ),
            ],
          ),
        ) ??
        false;
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

  Future<Area?> _selectRoomAfterRecognition(FirebaseService firebase) async {
    final snapshot = await firebase.firestore.collection('areas').get();
    final rooms =
        snapshot.docs
            .map((doc) => Area.fromMap(doc.id, doc.data()))
            .where((area) => area.active)
            .toList()
          ..sort(
            (a, b) => _roomSelectionLabel(a).compareTo(_roomSelectionLabel(b)),
          );
    if (!mounted) return null;
    if (rooms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active rooms are available.')),
      );
      return null;
    }
    var selectedArea = rooms.first;
    return showDialog<Area>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select Room'),
          content: DropdownButtonFormField<String>(
            initialValue: selectedArea.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Room'),
            items: [
              for (final room in rooms)
                DropdownMenuItem(
                  value: room.id,
                  child: Text(
                    _roomSelectionLabel(room),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setDialogState(() {
                selectedArea = rooms.firstWhere((room) => room.id == value);
              });
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selectedArea),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  String _roomSelectionLabel(Area area) {
    final room = area.roomNumber.trim();
    final name = area.name.trim();
    if (room.isNotEmpty && name.isNotEmpty) return '$room - $name';
    if (room.isNotEmpty) return room;
    if (name.isNotEmpty) return name;
    return area.id;
  }

  Area _activeAreaFromProvider() {
    final areas = context.read<AreaProvider>().areas;
    final scannerRoomId = _scannerRoomIdFromRoute();
    if (scannerRoomId != null) {
      for (final area in areas) {
        if (area.id == scannerRoomId ||
            _triNormalize(area.roomNumber) == _triNormalize(scannerRoomId) ||
            _triNormalize(_areaName(area)) == _triNormalize(scannerRoomId)) {
          return area;
        }
      }
    }
    final active = areas.where((area) => area.active).toList();
    for (final area in active) {
      if (_isRecognizedScannerRoom(area, _serverRoomName)) return area;
    }
    for (final area in active) {
      if (_isRecognizedScannerRoom(area, _ictOfficeName)) return area;
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

  String _scannerRoomDisplayLabel() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      final value =
          args['roomName'] ??
          args['areaName'] ??
          args['scannerRoomName'] ??
          args['label'];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return _areaName(_activeAreaFromProvider());
  }

  String _scannerSessionAction() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      final value = args['sessionAction'] ?? args['mode'] ?? args['event'];
      final action = value?.toString().trim().toLowerCase();
      if (action == 'exit' || action == 'logout') return 'exit';
    }
    return 'entry';
  }

  bool _isAppFaceLogin() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args == null) return true;
    if (args is Map<String, dynamic>) {
      final scannerKeys = [
        'roomId',
        'areaId',
        'scannerRoomId',
        'roomName',
        'areaName',
        'scannerRoomName',
        'sessionAction',
        'mode',
        'event',
      ];
      return !scannerKeys.any(
        (key) => args[key]?.toString().trim().isNotEmpty == true,
      );
    }
    return false;
  }

  String _triNormalize(String value) =>
      value.trim().toLowerCase().replaceAll(' ', '');

  bool _isRecognizedScannerRoom(Area area, String roomName) =>
      _triNormalize(_areaName(area)) == _triNormalize(roomName);

  bool _hasExplicitTemporalPolicy(SystemSettings system) {
    if (!system.afterHoursAlerts) return false;
    return system.afterHoursStart !=
            SystemSettings.defaults().afterHoursStart ||
        system.afterHoursEnd != SystemSettings.defaults().afterHoursEnd;
  }

  Future<bool> _hasSafeFrameLuminance(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final frame = img.decodeImage(bytes);
      if (frame == null) return false;
      final stepX = math.max(1, frame.width ~/ 48);
      final stepY = math.max(1, frame.height ~/ 48);
      var samples = 0;
      var total = 0.0;
      for (var y = 0; y < frame.height; y += stepY) {
        for (var x = 0; x < frame.width; x += stepX) {
          final pixel = frame.getPixel(x, y);
          total += (0.2126 * pixel.r) + (0.7152 * pixel.g) + (0.0722 * pixel.b);
          samples++;
        }
      }
      if (samples == 0) return false;
      return total / samples >= _minimumFrameLuminance;
    } catch (_) {
      return false;
    }
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
    final floor = area.floor.trim();
    final roomNumber = area.roomNumber.trim();
    if (name.isNotEmpty && floor.isNotEmpty) return '$floor - $name';
    if (name.isNotEmpty) return name;
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

  void _replaceWithAccessResult({
    required Object? user,
    required Object? log,
    Map<String, dynamic> extraArgs = const {},
  }) {
    if (isNavigating) return;
    isNavigating = true;
    final verifiedUser = user is AppUser ? user : null;
    final dashboardUser = verifiedUser ?? context.read<AuthProvider>().user;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        AccessResultScreen.route,
        (_) => false,
        arguments: {
          'user': user,
          'log': log,
          ...extraArgs,
          'dashboardRoute': dashboardUser == null
              ? LoginScreen.route
              : dashboardUser.isAdmin
              ? DashboardScreen.route
              : UserDashboardScreen.route,
          'backRoute': FaceLoginScreen.route,
        },
      );
    });
  }

  Future<void> _showSuccessAndNavigate(AppUser user, {AccessLog? log}) async {
    if (isNavigating) return;
    isNavigating = true;
    unawaited(_faceProvider?.closeDetector());
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AccessResultScreen.route,
      (_) => false,
      arguments: {
        'user': user,
        'log': log,
        'dashboardRoute': user.isAdmin
            ? DashboardScreen.route
            : UserDashboardScreen.route,
        'backRoute': FaceLoginScreen.route,
      },
    );
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
      final auth = context.read<AuthProvider>();
      final target = auth.hasSignedInAccount
          ? (auth.isAdmin ? DashboardScreen.route : UserDashboardScreen.route)
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
        backgroundColor: AppBackground.slateGray,
        body: SafeArea(
          child: Builder(
            builder: (context) {
              final lockedOut = settings.globalLockdown;
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
                    top: 14,
                    child: Row(
                      children: [
                        IconButton.filledTonal(
                          onPressed: _popAfterCameraRelease,
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Face Scan',
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_error != null || face.error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              _error ?? face.error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        const _ScannerInstructions(),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: (_busy || face.loading || lockedOut)
                                ? null
                                : () => _scan(settings),
                            style: FilledButton.styleFrom(
                              backgroundColor: CorporateColors.teal,
                              foregroundColor: const Color(0xFF02110F),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            child: _busy || face.loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.verified_user_rounded),
                                      SizedBox(width: 8),
                                      Text('Verify'),
                                    ],
                                  ),
                          ),
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

class _ScannerInstructions extends StatelessWidget {
  const _ScannerInstructions();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _InstructionLine('Position your face inside the frame to verify'),
        SizedBox(height: 5),
        _InstructionLine('Hold still while the system performs the scan'),
      ],
    );
  }
}

class _InstructionLine extends StatelessWidget {
  const _InstructionLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w800,
        shadows: [Shadow(color: Colors.black, blurRadius: 14)],
      ),
    );
  }
}
