import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
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
  const FaceAccessResult({
    required this.granted,
    this.match,
  });

  final bool granted;
  final RegisteredFaceMatch? match;
}

class MobileFaceAccessService {
  MobileFaceAccessService({
    FirebaseFirestore? firestore,
    this.threshold = 0.7,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        super();

  final FirebaseFirestore _firestore;
  final double threshold;

  // ignore: deprecated_member_use
  final FaceDetector _faceDetector = GoogleMlKit.vision.faceDetector(
    FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true,
      enableContours: false,
      enableClassification: false,
    ),
  );

  Future<Rect> getFaceBoundingBox(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final faces = await _faceDetector.processImage(inputImage);

    if (faces.isEmpty) {
      throw Exception('No face detected.');
    }
    if (faces.length > 1) {
      throw Exception('Multiple faces detected. Use one face only.');
    }

    return faces.first.boundingBox;
  }

  Future<Float32List> cropFaceToMobileFaceNetInput(String imagePath) async {
    final boundingBox = await getFaceBoundingBox(imagePath);
    final bytes = await img.decodeImageFile(imagePath);

    if (bytes == null) {
      throw Exception('Could not decode image.');
    }

    final left = boundingBox.left.clamp(0, bytes.width - 1).toInt();
    final top = boundingBox.top.clamp(0, bytes.height - 1).toInt();
    final width = boundingBox.width.clamp(1, bytes.width - left).toInt();
    final height = boundingBox.height.clamp(1, bytes.height - top).toInt();

    final cropped = img.copyCrop(
      bytes,
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

  void dispose() {
    _faceDetector.close();
  }
}
