import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
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

  static const int _legacyFrameWidth = 720;
  static const int _legacyFrameHeight = 480;

  final LocalDatabaseService localDb;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableClassification: true,
      minFaceSize: 0.2,
    ),
  );
  Interpreter? _faceNetInterpreter;
  Interpreter? _blazeFaceInterpreter;
  Future<void>? _initializing;
  Future<void> _detectorQueue = Future.value();
  DateTime? _lastDetectorStartedAt;

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
      faceNet = _createDynamicCpuInterpreter(faceNetBuffer);
      _allocateTensorsForRuntimeValidation(faceNet);
      _validateFaceNetModel(faceNet);

      final blazeFaceBuffer = await _loadBundledModelBuffer(
        FaceModelConfig.blazeFaceShortRangeAssetPath,
      );
      blazeFace = _createDynamicCpuInterpreter(blazeFaceBuffer);
      _allocateTensorsForRuntimeValidation(blazeFace);

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
        'The model asset at $assetPath is too small to be valid.',
      );
    }

    final hasTfliteIdentifier =
        bytes[4] == 0x54 &&
        bytes[5] == 0x46 &&
        bytes[6] == 0x4C &&
        bytes[7] == 0x33;
    if (!hasTfliteIdentifier) {
      throw FaceRecognitionException(
        'The model asset at $assetPath is not a valid face model binary.',
      );
    }
  }

  void _validateFaceNetModel(Interpreter interpreter) {
    _prepareDynamicTensorLayout(interpreter);
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

  Interpreter _createDynamicCpuInterpreter(Uint8List buffer) {
    final options = InterpreterOptions()
      ..threads = 2
      // Keep delegate selection dynamic. Static-only CPU delegate paths can
      // abandon camera buffers when runtime input tensors resize on-device.
      ..useNnApiForAndroid = false;
    try {
      return Interpreter.fromBuffer(buffer, options: options);
    } finally {
      options.delete();
    }
  }

  void _prepareDynamicTensorLayout(Interpreter interpreter) {
    _allocateTensorsForRuntimeValidation(interpreter);
  }

  void _allocateTensorsForRuntimeValidation(Interpreter interpreter) {
    try {
      interpreter.allocateTensors();
    } on Object catch (e) {
      throw FaceRecognitionException(
        'Face model tensor allocation failed before embedding comparison. '
        'The dynamic graph layout could not safely resize Tensor #137. Details: $e',
      );
    }
  }

  Future<List<_LocalFaceDetection>> _detectFaces(XFile file) async {
    return _runDetectorTask(() async {
      try {
        final faces = await _faceDetector
            .processImage(InputImage.fromFilePath(file.path))
            .timeout(const Duration(seconds: 8));
        return faces
            .map(
              (face) => _LocalFaceDetection(
                boundingBox: _LocalFaceBox(
                  left: face.boundingBox.left,
                  top: face.boundingBox.top,
                  width: face.boundingBox.width,
                  height: face.boundingBox.height,
                ),
              ),
            )
            .toList(growable: false);
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
    final faces = await _detectFaces(file);
    _validateSingleLiveFace(faces);
  }

  _LocalFaceDetection _validateSingleLiveFace(List<_LocalFaceDetection> faces) {
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
    if (face.boundingBox.width < 80 || face.boundingBox.height < 80) {
      throw const FaceRecognitionException(
        'Liveness check failed. Keep your face centered and close to the frame.',
      );
    }
    return face;
  }

  Future<List<double>> embeddingFromFile(XFile file) async {
    await initialize();
    final faces = await _detectFaces(file);
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
    final interpreter = _faceNetInterpreter!;
    _prepareDynamicTensorLayout(interpreter);
    interpreter.run(input, output);
    return _l2Normalize(output.first);
  }

  Future<List<double>> legacyEmbeddingFromFile(XFile file) async {
    await initialize();
    final faces = await _detectFaces(file);
    _validateSingleLiveFace(faces);
    final input = await Isolate.run(
      () => _prepareLegacyFaceNetInput(file.path),
    );
    final output = List.generate(
      1,
      (_) => List<double>.filled(FaceModelConfig.embeddingSize, 0),
    );
    final interpreter = _faceNetInterpreter!;
    _prepareDynamicTensorLayout(interpreter);
    interpreter.run(input, output);
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
    _lastDetectorStartedAt = null;
  }

  Future<void> close() async {
    await closeDetector();
    await _faceDetector.close();
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

class _LocalFaceDetection {
  const _LocalFaceDetection({required this.boundingBox});

  final _LocalFaceBox boundingBox;
}

class _LocalFaceBox {
  const _LocalFaceBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

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

List<List<List<List<double>>>> _prepareLegacyFaceNetInput(String path) {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) {
    throw const FaceRecognitionException('Could not read camera frame.');
  }
  final frame = _normalizeLegacyCameraFrame(decoded);
  final cropped = img.copyCrop(
    frame,
    x: (frame.width * .27).round(),
    y: (frame.height * .17).round(),
    width: (frame.width * .46).round(),
    height: (frame.height * .66).round(),
  );
  final resized = img.copyResize(
    cropped,
    width: FaceModelConfig.inputSize,
    height: FaceModelConfig.inputSize,
  );
  return _imageToFaceNetInput(resized);
}

List<List<List<List<double>>>> _imageToFaceNetInput(img.Image image) {
  return List.generate(
    1,
    (_) => List.generate(
      FaceModelConfig.inputSize,
      (y) => List.generate(FaceModelConfig.inputSize, (x) {
        final pixel = image.getPixel(x, y);
        return [
          (pixel.r - 127.5) / 128.0,
          (pixel.g - 127.5) / 128.0,
          (pixel.b - 127.5) / 128.0,
        ];
      }),
    ),
  );
}

img.Image _normalizeLegacyCameraFrame(img.Image source) {
  final portrait = source.height > source.width;
  final targetWidth = portrait
      ? FaceRecognitionService._legacyFrameHeight
      : FaceRecognitionService._legacyFrameWidth;
  final targetHeight = portrait
      ? FaceRecognitionService._legacyFrameWidth
      : FaceRecognitionService._legacyFrameHeight;
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
