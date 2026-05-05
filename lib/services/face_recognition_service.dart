import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'face_model_config.dart';
import 'local_database_service.dart';

class FaceRecognitionException implements Exception {
  const FaceRecognitionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class FaceRecognitionService {
  FaceRecognitionService(this.localDb);

  final LocalDatabaseService localDb;
  Interpreter? _faceNetInterpreter;
  Interpreter? _blazeFaceInterpreter;
  FaceDetector? _detector;
  Future<void>? _initializing;
  Future<void> _detectorQueue = Future.value();
  DateTime? _lastDetectorStartedAt;

  FaceDetector get _activeDetector =>
      // ignore: deprecated_member_use
      _detector ??= GoogleMlKit.vision.faceDetector(
        FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          enableContours: true,
          enableLandmarks: true,
          enableClassification: true,
        ),
      );

  Future<void> initialize() async {
    if (_faceNetInterpreter != null && _blazeFaceInterpreter != null) return;
    if (_initializing != null) return _initializing!;
    _initializing = _initializeInterpreters();
    try {
      await _initializing;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initializeInterpreters() async {
    Interpreter? faceNet;
    Interpreter? blazeFace;
    try {
      final faceNetBuffer = await _loadBundledModelBuffer(
        FaceModelConfig.assetPath,
      );
      faceNet = Interpreter.fromBuffer(faceNetBuffer);
      _validateFaceNetModel(faceNet);

      final blazeFaceBuffer = await _loadBundledModelBuffer(
        FaceModelConfig.blazeFaceShortRangeAssetPath,
      );
      blazeFace = Interpreter.fromBuffer(blazeFaceBuffer);

      _faceNetInterpreter = faceNet;
      _blazeFaceInterpreter = blazeFace;
    } on FaceRecognitionException {
      faceNet?.close();
      blazeFace?.close();
      rethrow;
    } on Object catch (e) {
      faceNet?.close();
      blazeFace?.close();
      final details = e.toString();
      if (details.contains('Unable to load asset')) {
        throw FaceRecognitionException(
          'Unable to load a face model asset. Expected ${FaceModelConfig.assetPath} and ${FaceModelConfig.blazeFaceShortRangeAssetPath}. '
          'Confirm pubspec.yaml registers the directory under flutter/assets and run flutter clean, then flutter pub get. '
          'Details: $e',
        );
      }
      if (details.toLowerCase().contains('empty data')) {
        throw FaceRecognitionException(
          'A bundled face model loaded as empty data. Replace it with a real .tflite binary and confirm the asset path is registered.',
        );
      }
      throw FaceRecognitionException(
        'Face model missing, unreadable, or invalid. Expected MobileFaceNet at ${FaceModelConfig.assetPath} and BlazeFace short-range at ${FaceModelConfig.blazeFaceShortRangeAssetPath}. Details: $e',
      );
    }
  }

  Future<Uint8List> _loadBundledModelBuffer(String assetPath) async {
    final ByteData byteData = await rootBundle.load(assetPath);
    if (byteData.lengthInBytes <= 0) {
      throw FaceRecognitionException(
        'The model asset at $assetPath is bundled but contains empty data.',
      );
    }
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    _validateModelBuffer(assetPath, bytes);
    return bytes;
  }

  void _validateModelBuffer(String assetPath, Uint8List bytes) {
    if (bytes.isEmpty) {
      throw FaceRecognitionException(
        'The model asset at $assetPath is bundled but contains empty data.',
      );
    }
    if (bytes.lengthInBytes < 8) {
      throw FaceRecognitionException(
        'The model asset at $assetPath is too small to be a valid TFLite model.',
      );
    }

    final hasTfliteIdentifier =
        bytes[4] == 0x54 &&
        bytes[5] == 0x46 &&
        bytes[6] == 0x4C &&
        bytes[7] == 0x33;
    if (!hasTfliteIdentifier) {
      throw FaceRecognitionException(
        'The model asset at $assetPath is not a valid TensorFlow Lite flatbuffer. Replace it with the real .tflite binary.',
      );
    }
  }

  void _validateFaceNetModel(Interpreter interpreter) {
    final inputShape = interpreter.getInputTensor(0).shape;
    final outputShape = interpreter.getOutputTensor(0).shape;
    final hasExpectedInput =
        inputShape.length == 4 &&
        inputShape[0] == 1 &&
        inputShape[1] == FaceModelConfig.inputSize &&
        inputShape[2] == FaceModelConfig.inputSize &&
        inputShape[3] == 3;
    final hasExpectedOutput =
        outputShape.length == 2 &&
        outputShape[0] == 1 &&
        outputShape[1] == FaceModelConfig.embeddingSize;

    if (!hasExpectedInput || !hasExpectedOutput) {
      interpreter.close();
      throw FaceRecognitionException(
        'Unsupported face model shape. Expected input [1, ${FaceModelConfig.inputSize}, ${FaceModelConfig.inputSize}, 3] and output [1, ${FaceModelConfig.embeddingSize}], but got input $inputShape and output $outputShape.',
      );
    }
  }

  Future<List<Face>> detectFaces(XFile file) async {
    return _runDetectorTask(() async {
      final input = InputImage.fromFilePath(file.path);
      try {
        return await _activeDetector
            .processImage(input)
            .timeout(const Duration(seconds: 8));
      } on TimeoutException {
        throw const FaceRecognitionException(
          'Face detection timed out. Try brighter lighting and keep your face centered.',
        );
      }
    });
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

  Future<void> validateLiveness(XFile file) async {
    final faces = await detectFaces(file);
    _validateSingleLiveFace(faces);
  }

  Face _validateSingleLiveFace(List<Face> faces) {
    if (faces.isEmpty) {
      throw const FaceRecognitionException(
        'No live face detected. Center your face in the guide.',
      );
    }
    if (faces.length > 1) {
      throw const FaceRecognitionException(
        'Multiple faces detected. Scan one person at a time.',
      );
    }
    final face = faces.first;
    final leftOpen = face.leftEyeOpenProbability;
    final rightOpen = face.rightEyeOpenProbability;
    final hasOpenEyes =
        leftOpen == null ||
        rightOpen == null ||
        (leftOpen > .35 && rightOpen > .35);
    final headY = (face.headEulerAngleY ?? 0).abs();
    final headZ = (face.headEulerAngleZ ?? 0).abs();
    final hasNaturalPose = headY < 25 && headZ < 20;
    if (!hasOpenEyes || !hasNaturalPose) {
      throw const FaceRecognitionException(
        'Liveness check failed. Keep your face upright with both eyes visible.',
      );
    }
    return face;
  }

  Future<List<double>> embeddingFromFile(XFile file) async {
    await initialize();
    final faces = await detectFaces(file);
    final face = _validateSingleLiveFace(faces).boundingBox;
    final input = await Isolate.run(
      () => _prepareFaceNetInput(
        _FaceCropRequest(
          path: file.path,
          left: face.left,
          top: face.top,
          width: face.width,
          height: face.height,
        ),
      ),
    );
    final output = List.generate(
      1,
      (_) => List<double>.filled(FaceModelConfig.embeddingSize, 0),
    );
    _faceNetInterpreter!.run(input, output);
    return _l2Normalize(output.first);
  }

  Future<List<double>> averageEmbeddings(List<XFile> captures) async {
    if (captures.length < 3) {
      throw const FaceRecognitionException(
        'Capture three face samples before registering.',
      );
    }
    final embeddings = <List<double>>[];
    for (final file in captures) {
      embeddings.add(await embeddingFromFile(file));
    }
    final avg = List<double>.filled(FaceModelConfig.embeddingSize, 0);
    for (final emb in embeddings) {
      for (var i = 0; i < avg.length; i++) {
        avg[i] += emb[i] / embeddings.length;
      }
    }
    return _l2Normalize(avg);
  }

  Future<LocalFaceMatch?> identify(XFile capture) async {
    final emb = await embeddingFromFile(capture);
    return localDb.findNearestFace(emb);
  }

  List<double> _l2Normalize(List<double> input) {
    final norm = math.sqrt(input.fold<double>(0, (sum, v) => sum + v * v));
    if (norm == 0) return input;
    return input.map((e) => e / norm).toList();
  }

  Future<void> closeDetector() async {
    await _detectorQueue.catchError((_) {});
    await _detector?.close();
    _detector = null;
    _lastDetectorStartedAt = null;
  }

  Future<void> close() async {
    await closeDetector();
    _faceNetInterpreter?.close();
    _blazeFaceInterpreter?.close();
    _faceNetInterpreter = null;
    _blazeFaceInterpreter = null;
  }
}

class _FaceCropRequest {
  const _FaceCropRequest({
    required this.path,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String path;
  final double left;
  final double top;
  final double width;
  final double height;
}

List<List<List<List<double>>>> _prepareFaceNetInput(_FaceCropRequest request) {
  final decoded = img.decodeImage(File(request.path).readAsBytesSync());
  if (decoded == null) {
    throw const FaceRecognitionException('Could not read camera frame.');
  }

  final left = request.left.clamp(0, decoded.width - 1).toInt();
  final top = request.top.clamp(0, decoded.height - 1).toInt();
  final width = request.width.clamp(1, decoded.width - left).toInt();
  final height = request.height.clamp(1, decoded.height - top).toInt();
  final cropped = img.copyCrop(
    decoded,
    x: left,
    y: top,
    width: width,
    height: height,
  );
  final resized = img.copyResize(
    cropped,
    width: FaceModelConfig.inputSize,
    height: FaceModelConfig.inputSize,
  );
  return List.generate(
    1,
    (_) => List.generate(
      FaceModelConfig.inputSize,
      (y) => List.generate(FaceModelConfig.inputSize, (x) {
        final pixel = resized.getPixel(x, y);
        return [
          (pixel.r - 127.5) / 128.0,
          (pixel.g - 127.5) / 128.0,
          (pixel.b - 127.5) / 128.0,
        ];
      }),
    ),
  );
}
