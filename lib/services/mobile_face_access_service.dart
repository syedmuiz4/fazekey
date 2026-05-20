import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image/image.dart' as img;

class RegisteredFaceMatch {
  const RegisteredFaceMatch({
    required this.userId,
    required this.name,
    required this.distance,
  });

  final String userId;
  final String name;
  final double distance;
}

class FaceAccessResult {
  const FaceAccessResult({required this.granted, this.match});

  final bool granted;
  final RegisteredFaceMatch? match;
}

class MobileFaceAccessService {
  MobileFaceAccessService({FirebaseFirestore? firestore, this.threshold = 1.2})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      super();

  static const int _staticFrameWidth = 720;
  static const int _staticFrameHeight = 480;

  final FirebaseFirestore _firestore;
  final double threshold;
  Future<void> _detectorQueue = Future.value();
  DateTime? _lastDetectorStartedAt;

  Future<Rect> getFaceBoundingBox(String imagePath) async {
    final faces = await _runDetectorTask(
      () async => Isolate.run(() => _standaloneFaceBoxes(imagePath)),
    );

    if (faces.isEmpty) {
      throw Exception('No face detected.');
    }
    if (faces.length > 1) {
      throw Exception('Multiple faces detected. Use one face only.');
    }

    return faces.first;
  }

  Future<Float32List> cropFaceToMobileFaceNetInput(String imagePath) async {
    final boundingBox = await getFaceBoundingBox(imagePath);
    return Isolate.run(
      () => _cropFaceToMobileFaceNetInput(
        _MobileFaceCropRequest(
          imagePath: imagePath,
          left: boundingBox.left,
          top: boundingBox.top,
          width: boundingBox.width,
          height: boundingBox.height,
        ),
      ),
    );
  }

  Future<T> _runDetectorTask<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _detectorQueue = _detectorQueue.catchError((_) {}).then((_) async {
      if (completer.isCompleted) return;
      try {
        await _throttleDetector();
        completer.complete(await task());
      } catch (e, stackTrace) {
        completer.completeError(e, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _throttleDetector() async {
    final lastStartedAt = _lastDetectorStartedAt;
    if (lastStartedAt != null) {
      final elapsed = DateTime.now().difference(lastStartedAt);
      const minimumGap = Duration(milliseconds: 500);
      if (elapsed < minimumGap) {
        await Future<void>.delayed(minimumGap - elapsed);
      }
    }
    _lastDetectorStartedAt = DateTime.now();
  }

  Future<List<RegisteredFaceMatch>> loadRegisteredFaceDistances(
    List<double> currentEmbedding,
  ) async {
    final users = await _firestore
        .collection('users')
        .where('hasFace', isEqualTo: true)
        .get();

    final matches = <RegisteredFaceMatch>[];

    for (final doc in users.docs) {
      final data = doc.data();
      final rawEmbedding = data['faceEmbedding'];

      if (rawEmbedding is! List) continue;

      final registeredEmbedding = rawEmbedding
          .map((value) => (value as num).toDouble())
          .toList(growable: false);

      if (registeredEmbedding.length != currentEmbedding.length) continue;

      matches.add(
        RegisteredFaceMatch(
          userId: doc.id,
          name: (data['name'] as String?) ?? 'Unknown user',
          distance: euclideanDistance(currentEmbedding, registeredEmbedding),
        ),
      );
    }

    matches.sort((a, b) => a.distance.compareTo(b.distance));
    return matches;
  }

  Future<FaceAccessResult> checkAccess(List<double> currentEmbedding) async {
    final matches = await loadRegisteredFaceDistances(currentEmbedding);
    final bestMatch = matches.isEmpty ? null : matches.first;
    final granted = bestMatch != null && bestMatch.distance < threshold;

    if (granted) {
      await triggerAccessGranted(bestMatch);
    }

    return FaceAccessResult(granted: granted, match: bestMatch);
  }

  Future<void> triggerAccessGranted(RegisteredFaceMatch match) {
    return _firestore.collection('accessLogs').add({
      'userId': match.userId,
      'userName': match.name,
      'status': 'granted',
      'reason': 'Face matched below threshold $threshold',
      'distance': match.distance,
      'timestamp': FieldValue.serverTimestamp(),
      'synced': true,
    });
  }

  double euclideanDistance(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('Embedding lengths must match.');
    }

    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }

    return math.sqrt(sum);
  }

  Future<void> dispose() async {
    await _detectorQueue.catchError((_) {});
    _lastDetectorStartedAt = null;
  }
}

class _MobileFaceCropRequest {
  const _MobileFaceCropRequest({
    required this.imagePath,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String imagePath;
  final double left;
  final double top;
  final double width;
  final double height;
}

List<Rect> _standaloneFaceBoxes(String imagePath) {
  final bytes = img.decodeImage(File(imagePath).readAsBytesSync());
  if (bytes == null) {
    throw Exception('Could not decode image.');
  }
  final frame = _normalizeCameraFrame(bytes);
  return [
    Rect.fromLTWH(
      frame.width * .27,
      frame.height * .17,
      frame.width * .46,
      frame.height * .66,
    ),
  ];
}

Float32List _cropFaceToMobileFaceNetInput(_MobileFaceCropRequest request) {
  final bytes = img.decodeImage(File(request.imagePath).readAsBytesSync());

  if (bytes == null) {
    throw Exception('Could not decode image.');
  }

  final staticFrame = _normalizeCameraFrame(bytes);
  final left = request.left.clamp(0, staticFrame.width - 1).toInt();
  final top = request.top.clamp(0, staticFrame.height - 1).toInt();
  final width = request.width.clamp(1, staticFrame.width - left).toInt();
  final height = request.height.clamp(1, staticFrame.height - top).toInt();

  final cropped = img.copyCrop(
    staticFrame,
    x: left,
    y: top,
    width: width,
    height: height,
  );
  final resized = img.copyResize(cropped, width: 112, height: 112);

  final input = Float32List(1 * 112 * 112 * 3);
  var index = 0;

  for (var y = 0; y < 112; y++) {
    for (var x = 0; x < 112; x++) {
      final pixel = resized.getPixel(x, y);
      input[index++] = (pixel.r - 127.5) / 128.0;
      input[index++] = (pixel.g - 127.5) / 128.0;
      input[index++] = (pixel.b - 127.5) / 128.0;
    }
  }

  return input;
}

img.Image _normalizeCameraFrame(img.Image source) {
  final portrait = source.height > source.width;
  final targetWidth = portrait
      ? MobileFaceAccessService._staticFrameHeight
      : MobileFaceAccessService._staticFrameWidth;
  final targetHeight = portrait
      ? MobileFaceAccessService._staticFrameWidth
      : MobileFaceAccessService._staticFrameHeight;
  final targetAspect = targetWidth / targetHeight;
  final sourceAspect = source.width / source.height;
  var cropX = 0;
  var cropY = 0;
  var cropWidth = source.width;
  var cropHeight = source.height;
  if (sourceAspect > targetAspect) {
    cropWidth = (source.height * targetAspect)
        .round()
        .clamp(1, source.width)
        .toInt();
    cropX = ((source.width - cropWidth) / 2).round();
  } else if (sourceAspect < targetAspect) {
    cropHeight = (source.width / targetAspect)
        .round()
        .clamp(1, source.height)
        .toInt();
    cropY = ((source.height - cropHeight) / 2).round();
  }
  final cropped = img.copyCrop(
    source,
    x: cropX,
    y: cropY,
    width: cropWidth,
    height: cropHeight,
  );
  return img.copyResize(cropped, width: targetWidth, height: targetHeight);
}
