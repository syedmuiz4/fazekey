import 'dart:async';
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
  // ignore: deprecated_member_use
  final FaceDetector _detector = GoogleMlKit.vision.faceDetector(
    FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableContours: true,
      enableLandmarks: true,
      enableClassification: true,
    ),
  );
  Interpreter? _interpreter;
  Future<void>? _initializing;

  Future<void> initialize() async {
    if (_interpreter != null) return;
    if (_initializing != null) return _initializing!;
    _initializing = _initializeInterpreter();
    try {
      await _initializing;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initializeInterpreter() async {
    try {
      final modelBuffer = await _loadBundledModelBuffer();
      final interpreter = Interpreter.fromBuffer(modelBuffer);
      _validateModel(interpreter);
      _interpreter = interpreter;
    } on FaceRecognitionException {
      rethrow;
    } on Object catch (e) {
      final details = e.toString();
      if (details.contains('Unable to load asset')) {
        throw FaceRecognitionException(
          'Unable to load face model asset at ${FaceModelConfig.assetPath}. '
          'Confirm pubspec.yaml registers the directory under flutter/assets and run flutter clean, then flutter pub get. '
          'Details: $e',
        );
      }
      if (details.toLowerCase().contains('empty data')) {
        throw FaceRecognitionException(
          'The bundled face model at ${FaceModelConfig.assetPath} loaded as empty data. '
          'Replace it with a real MobileFaceNet .tflite binary and confirm the asset path is registered.',
        );
      }
      throw FaceRecognitionException(
        'Face model missing, unreadable, or invalid at ${FaceModelConfig.assetPath}. '
        'Add a real MobileFaceNet TFLite binary at that path. Details: $e',
      );
    }
  }

  Future<Uint8List> _loadBundledModelBuffer() async {
    final byteData = await rootBundle.load(FaceModelConfig.assetPath);
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    _validateModelBuffer(bytes);
    return bytes;
  }

  void _validateModelBuffer(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw FaceRecognitionException(
        'The face model asset at ${FaceModelConfig.assetPath} is bundled but contains empty data.',
      );
    }
    if (bytes.lengthInBytes < 8) {
      throw FaceRecognitionException(
        'The face model asset at ${FaceModelConfig.assetPath} is too small to be a valid TFLite model.',
      );
    }

    final hasTfliteIdentifier = bytes[4] == 0x54 &&
        bytes[5] == 0x46 &&
        bytes[6] == 0x4C &&
        bytes[7] == 0x33;
    if (!hasTfliteIdentifier) {
      throw FaceRecognitionException(
        'The face model asset at ${FaceModelConfig.assetPath} is not a valid TensorFlow Lite flatbuffer. '
        'Replace the current file with the actual MobileFaceNet .tflite binary.',
      );
    }
  }

  void _validateModel(Interpreter interpreter) {
    final inputShape = interpreter.getInputTensor(0).shape;
    final outputShape = interpreter.getOutputTensor(0).shape;
    final hasExpectedInput = inputShape.length == 4 &&
        inputShape[0] == 1 &&
        inputShape[1] == FaceModelConfig.inputSize &&
        inputShape[2] == FaceModelConfig.inputSize &&
        inputShape[3] == 3;
    final hasExpectedOutput = outputShape.length == 2 &&
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
    final input = InputImage.fromFilePath(file.path);
    try {
      return await _detector.processImage(input).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw const FaceRecognitionException('Face detection timed out. Try brighter lighting and keep your face centered.');
    }
  }

  Future<void> validateLiveness(XFile file) async {
    final faces = await detectFaces(file);
    if (faces.isEmpty) {
      throw const FaceRecognitionException('No live face detected. Center your face in the guide.');
    }
    if (faces.length > 1) {
      throw const FaceRecognitionException('Multiple faces detected. Scan one person at a time.');
    }
    final face = faces.first;
    final leftOpen = face.leftEyeOpenProbability;
    final rightOpen = face.rightEyeOpenProbability;
    final hasOpenEyes = leftOpen == null || rightOpen == null || (leftOpen > .35 && rightOpen > .35);
    final headY = (face.headEulerAngleY ?? 0).abs();
    final headZ = (face.headEulerAngleZ ?? 0).abs();
    final hasNaturalPose = headY < 25 && headZ < 20;
    if (!hasOpenEyes || !hasNaturalPose) {
      throw const FaceRecognitionException('Liveness check failed. Keep your face upright with both eyes visible.');
    }
  }

  Future<List<double>> embeddingFromFile(XFile file) async {
    await initialize();
    await validateLiveness(file);
    final faces = await detectFaces(file);
    if (faces.isEmpty) {
      throw const FaceRecognitionException('No face detected. Center your face in the guide.');
    }
    if (faces.length > 1) {
      throw const FaceRecognitionException('Multiple faces detected. Use one person at a time.');
    }
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FaceRecognitionException('Could not read camera frame.');
    }
    final face = faces.first.boundingBox;
    final left = face.left.clamp(0, decoded.width - 1).toInt();
    final top = face.top.clamp(0, decoded.height - 1).toInt();
    final width = face.width.clamp(1, decoded.width - left).toInt();
    final height = face.height.clamp(1, decoded.height - top).toInt();
    final cropped = img.copyCrop(decoded, x: left, y: top, width: width, height: height);
    final resized = img.copyResize(
      cropped,
      width: FaceModelConfig.inputSize,
      height: FaceModelConfig.inputSize,
    );
    final input = List.generate(
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
    final output = List.generate(
      1,
      (_) => List<double>.filled(FaceModelConfig.embeddingSize, 0),
    );
    _interpreter!.run(input, output);
    return _l2Normalize(output.first);
  }

  Future<List<double>> averageEmbeddings(List<XFile> captures) async {
    if (captures.length < 3) {
      throw const FaceRecognitionException('Capture three face samples before registering.');
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

  Future<void> close() async {
    await _detector.close();
    _interpreter?.close();
    _interpreter = null;
  }
}
