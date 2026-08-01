import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'tflite_flatbuffer.dart';

/// ---------------------------------------------------------------------------
/// ModelMetadata — an immutable, self-describing snapshot of the loaded model.
///
/// Every value is derived **at runtime** from the TFLite interpreter (the
/// single source of truth) or from the model buffer itself. Nothing is
/// hardcoded: not the datatype, not the shapes, not the quantization
/// assumptions, not the model name.
/// ---------------------------------------------------------------------------

/// Human-readable classification of a model's numeric precision.
///
/// Detected from runtime I/O tensor metadata plus an internal tensor-type scan
/// of the model buffer. Never guessed from filenames.
enum ModelType {
  fp32('FP32'),
  fullInt8('Full INT8 Quantized'),
  fullUint8('Full UINT8 Quantized'),
  weightQuantized('Weight-Quantized'),
  unknown('Unknown (internal tensor precision unavailable)');

  final String label;

  const ModelType(this.label);
}

class ModelMetadata {
  // Identity
  final String modelName;

  // Input tensor
  final TensorType inputType;
  final List<int> inputShape;
  final double inputScale;
  final int inputZeroPoint;

  // Output tensor
  final TensorType outputType;
  final List<int> outputShape;
  final double outputScale;
  final int outputZeroPoint;

  // Quantization state
  final bool inputQuantized;
  final bool outputQuantized;
  final bool requiresInputQuantization;
  final bool requiresOutputDequantization;

  // Detection-model derived values (YOLO [1, 4 + C, N] convention)
  final int classes;
  final int anchors;

  // Classified precision (FP32 / Full INT8 / Full UINT8 / Weight-Quantized /
  // Unknown).
  final ModelType modelType;

  /// Flatbuffer tensor-type codes → count across the primary subgraph.
  /// `null` when the internal scan was unavailable (type then = Unknown).
  final Map<int, int>? internalTensorTypeCounts;

  const ModelMetadata({
    required this.modelName,
    required this.inputType,
    required this.outputType,
    required this.inputShape,
    required this.outputShape,
    required this.inputScale,
    required this.inputZeroPoint,
    required this.outputScale,
    required this.outputZeroPoint,
    required this.inputQuantized,
    required this.outputQuantized,
    required this.requiresInputQuantization,
    required this.requiresOutputDequantization,
    required this.classes,
    required this.anchors,
    required this.modelType,
    required this.internalTensorTypeCounts,
  });

  /// A tensor requires manual quantize/dequantize handling when it is a
  /// quantized integer type (INT8 / UINT8 / INT16).
  static bool isQuantizedType(TensorType type) =>
      type == TensorType.int8 ||
      type == TensorType.uint8 ||
      type == TensorType.int16;

  /// Floating-point tensor types that flow through without integer
  /// (de)quantization math.
  static bool isFloatType(TensorType type) =>
      type == TensorType.float32 ||
      type == TensorType.float16 ||
      type == TensorType.float64;

  /// Number of elements implied by [shape].
  static int elementCount(List<int> shape) =>
      shape.fold(1, (a, b) => a * b);

  /// -------------------------------------------------------------------------
  /// Runtime inspection — build metadata straight from the interpreter.
  /// -------------------------------------------------------------------------
  static ModelMetadata inspect({
    required String modelName,
    required Tensor inputTensor,
    required Tensor outputTensor,
    required Uint8List modelBytes,
  }) {
    final inputShape = List<int>.unmodifiable(inputTensor.shape);
    final outputShape = List<int>.unmodifiable(outputTensor.shape);

    final inputQuantized = isQuantizedType(inputTensor.type);
    final outputQuantized = isQuantizedType(outputTensor.type);

    // Scan internal tensor precision for the model-type classification.
    // Fails soft: null → classified as Unknown (never guessed).
    final internalTypes = scanTfliteTensorTypeCounts(modelBytes);
    if (internalTypes == null) {
      debugPrint(
        '[Model] Internal tensor scan unavailable — model type reported as '
        '"${ModelType.unknown.label}"',
      );
    }

    // Derived detection values. The parser operates on YOLO-style outputs of
    // shape [1, 4 + C, N]. Anything else yields -1 and is logged.
    final int classes;
    final int anchors;
    if (outputShape.length == 3) {
      classes = outputShape[1] - 4;
      anchors = outputShape[2];
      if (classes < 1 || anchors < 1) {
        debugPrint(
          '[Model] Output shape $outputShape does not match the expected '
          'detection layout [1, 4+C, N] — classes/anchors will be -1',
        );
      }
    } else {
      classes = -1;
      anchors = -1;
      debugPrint(
        '[Model] Output shape $outputShape is not 3-D — classes/anchors '
        'cannot be derived',
      );
    }

    return ModelMetadata(
      modelName: modelName,
      inputType: inputTensor.type,
      outputType: outputTensor.type,
      inputShape: inputShape,
      outputShape: outputShape,
      inputScale: inputTensor.params.scale,
      inputZeroPoint: inputTensor.params.zeroPoint,
      outputScale: outputTensor.params.scale,
      outputZeroPoint: outputTensor.params.zeroPoint,
      inputQuantized: inputQuantized,
      outputQuantized: outputQuantized,
      requiresInputQuantization: inputQuantized,
      requiresOutputDequantization: outputQuantized,
      classes: classes,
      anchors: anchors,
      modelType: detectModelType(
        inputType: inputTensor.type,
        outputType: outputTensor.type,
        internalTensorTypeCounts: internalTypes,
      ),
      internalTensorTypeCounts: internalTypes,
    );
  }

  /// -------------------------------------------------------------------------
  /// Dynamic model-type detection. Never guesses.
  ///
  /// * INT8 I/O            → Full INT8 Quantized
  /// * UINT8 I/O           → Full UINT8 Quantized
  /// * FLOAT32 I/O + quantized internal weights → Weight-Quantized
  /// * FLOAT32 I/O + no quantized internal weights → FP32
  /// * Internal scan unavailable → Unknown
  /// -------------------------------------------------------------------------
  static ModelType detectModelType({
    required TensorType inputType,
    required TensorType outputType,
    required Map<int, int>? internalTensorTypeCounts,
  }) {
    final inputQuantized = isQuantizedType(inputType);
    final outputQuantized = isQuantizedType(outputType);

    if (inputQuantized && outputQuantized) {
      return inputType == TensorType.int8
          ? ModelType.fullInt8
          : ModelType.fullUint8;
    }

    // Float I/O: distinguish pure FP32 from weight-quantized by scanning the
    // internal tensors. If the scan is unavailable, report Unknown — do NOT
    // guess.
    if (internalTensorTypeCounts == null) {
      return ModelType.unknown;
    }

    final hasQuantizedWeights = internalTensorTypeCounts.keys.any(
      (code) =>
          code == TfliteFlatTensorType.int8 ||
          code == TfliteFlatTensorType.uint8 ||
          code == TfliteFlatTensorType.int16 ||
          code == TfliteFlatTensorType.float16,
    );
    return hasQuantizedWeights ? ModelType.weightQuantized : ModelType.fp32;
  }

  /// -------------------------------------------------------------------------
  /// Isolate-safe serialization (metadata is built inside the inference
  /// isolate and shipped to the main isolate for display).
  /// -------------------------------------------------------------------------
  Map<String, dynamic> toJsonMap() => {
        'modelName': modelName,
        'inputType': inputType.name,
        'outputType': outputType.name,
        'inputShape': inputShape,
        'outputShape': outputShape,
        'inputScale': inputScale,
        'inputZeroPoint': inputZeroPoint,
        'outputScale': outputScale,
        'outputZeroPoint': outputZeroPoint,
        'inputQuantized': inputQuantized,
        'outputQuantized': outputQuantized,
        'requiresInputQuantization': requiresInputQuantization,
        'requiresOutputDequantization': requiresOutputDequantization,
        'classes': classes,
        'anchors': anchors,
        'modelType': modelType.name,
        'internalTensorTypeCounts': internalTensorTypeCounts,
      };

  factory ModelMetadata.fromJsonMap(Map<String, dynamic> json) {
    final internalRaw = json['internalTensorTypeCounts'] as Map<dynamic, dynamic>?;
    final internalTypes = internalRaw == null
        ? null
        : <int, int>{
            for (final e in internalRaw.entries) e.key as int: e.value as int,
          };

    return ModelMetadata(
      modelName: json['modelName'] as String,
      inputType: _tensorTypeFromName(json['inputType'] as String),
      outputType: _tensorTypeFromName(json['outputType'] as String),
      inputShape: (json['inputShape'] as List).cast<int>(),
      outputShape: (json['outputShape'] as List).cast<int>(),
      inputScale: (json['inputScale'] as num).toDouble(),
      inputZeroPoint: json['inputZeroPoint'] as int,
      outputScale: (json['outputScale'] as num).toDouble(),
      outputZeroPoint: json['outputZeroPoint'] as int,
      inputQuantized: json['inputQuantized'] as bool,
      outputQuantized: json['outputQuantized'] as bool,
      requiresInputQuantization: json['requiresInputQuantization'] as bool,
      requiresOutputDequantization: json['requiresOutputDequantization'] as bool,
      classes: json['classes'] as int,
      anchors: json['anchors'] as int,
      modelType: ModelType.values.firstWhere(
        (t) => t.name == (json['modelType'] as String),
        orElse: () => ModelType.unknown,
      ),
      internalTensorTypeCounts: internalTypes,
    );
  }

  static TensorType _tensorTypeFromName(String name) =>
      TensorType.values.firstWhere(
        (t) => t.name == name,
        orElse: () => TensorType.noType,
      );

  @override
  String toString() {
    return 'ModelMetadata('
        'model: $modelName, type: ${modelType.label}, '
        'input: ${inputType.name} ${inputShape.join('×')}, '
        'output: ${outputType.name} ${outputShape.join('×')}, '
        'classes: $classes, anchors: $anchors)';
  }
}
