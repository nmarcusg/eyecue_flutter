import 'dart:math' as math;
import 'dart:typed_data';

/// ---------------------------------------------------------------------------
/// TFLite flatbuffer introspection (pure Dart, no Flutter / no FFI).
///
/// The classic TFLite Dart runtime API only exposes **input and output**
/// tensors. To learn the *internal* tensor precision — e.g. whether a model
/// with FLOAT32 I/O actually carries quantized INT8/INT16 weights — we walk the
/// raw `.tflite` flatbuffer ourselves.
///
/// The FlatBuffers algorithm used here was validated against the reference
/// `tflite` Python package on both bundled models (tensor-type counts match
/// exactly). If parsing fails for any reason the scan returns `null`; callers
/// must then report precision as "Unknown" and must **never guess**.
/// ---------------------------------------------------------------------------

/// Flatbuffer `TensorType` enum codes as declared in the TFLite `schema.fbs`.
///
/// Note: these codes differ from the C-API `TfLiteType` numbering used by
/// the classic runtime (e.g. flatbuffer `FLOAT32 = 0` while `TfLiteType
/// kTfLiteFloat32 = 1`), so they are declared independently here.
class TfliteFlatTensorType {
  static const int float32 = 0;
  static const int float16 = 1;
  static const int int32 = 2;
  static const int uint8 = 3;
  static const int int64 = 4;
  static const int string = 5;
  static const int boolean = 6;
  static const int int16 = 7;
  static const int complex64 = 8;
  static const int int8 = 9;
  static const int float64 = 10;
  static const int complex128 = 11;
  static const int uint64 = 12;
  static const int resource = 13;
  static const int variant = 14;
  static const int uint32 = 15;
  static const int uint16 = 16;
  static const int int4 = 17;

  const TfliteFlatTensorType._();
}

/// The structural metadata for one tensor in the primary TFLite subgraph.
///
/// This intentionally contains only FlatBuffer metadata.  It does not expose
/// the tensor buffer contents, so it is safe to use when validating that a
/// packaging-only operation has not changed the graph.
class TfliteTensorInfo {
  final int index;
  final int typeCode;
  final List<int> shape;
  final int bufferIndex;

  const TfliteTensorInfo({
    required this.index,
    required this.typeCode,
    required this.shape,
    required this.bufferIndex,
  });

  Map<String, dynamic> toJsonMap() => {
    'index': index,
    'typeCode': typeCode,
    'shape': shape,
    'bufferIndex': bufferIndex,
  };
}

/// A pure-Dart structural snapshot of a TFLite model's primary subgraph.
///
/// The runtime interpreter exposes input/output tensors, but not the complete
/// internal tensor list.  This snapshot supplies the missing static evidence
/// needed by model packaging validators: input/output indices and metadata,
/// plus the internal tensor-type histogram.
class TfliteModelStructure {
  final List<TfliteTensorInfo> tensors;
  final List<int> inputs;
  final List<int> outputs;
  final Map<int, int> tensorTypeCounts;

  const TfliteModelStructure({
    required this.tensors,
    required this.inputs,
    required this.outputs,
    required this.tensorTypeCounts,
  });

  List<TfliteTensorInfo> get inputTensors => _tensorsAt(inputs);

  List<TfliteTensorInfo> get outputTensors => _tensorsAt(outputs);

  Map<String, dynamic> toJsonMap() => {
    'inputs': inputs,
    'outputs': outputs,
    'inputTensors': inputTensors.map((tensor) => tensor.toJsonMap()).toList(),
    'outputTensors': outputTensors.map((tensor) => tensor.toJsonMap()).toList(),
    'tensors': tensors.map((tensor) => tensor.toJsonMap()).toList(),
    'tensorTypeCounts': tensorTypeCounts.map(
      (key, value) => MapEntry(key.toString(), value),
    ),
  };

  List<TfliteTensorInfo> _tensorsAt(List<int> indices) => [
    for (final index in indices)
      if (index >= 0 && index < tensors.length) tensors[index],
  ];
}

/// Scans the primary subgraph of a TFLite model and returns its structural
/// tensor metadata.
///
/// Returns `null` when the buffer cannot be parsed.  Appended ZIP bytes are
/// harmless because FlatBuffers resolve all model objects from the root table
/// at offset zero.
TfliteModelStructure? scanTfliteModelStructure(Uint8List modelBytes) {
  try {
    final reader = _FlatBufferReader(modelBytes);

    // Root table is `Model`. `Model.subgraphs` is field index 2.
    final root = reader.u32(0);
    final subgraphsField = reader.fieldPos(root, 2);
    if (subgraphsField == 0) return null;
    final subgraphsVector = reader.indirect(subgraphsField);
    final subgraphCount = reader.vectorLength(subgraphsVector);
    if (subgraphCount < 1) return null;

    // Primary subgraph. `SubGraph.tensors` is field index 0.
    final subgraph = reader.vectorElementIndirect(subgraphsVector, 0);
    final tensorsField = reader.fieldPos(subgraph, 0);
    if (tensorsField == 0) return null;
    final tensorsVector = reader.indirect(tensorsField);
    final tensorCount = reader.vectorLength(tensorsVector);

    final tensors = <TfliteTensorInfo>[];
    final counts = <int, int>{};
    for (var i = 0; i < tensorCount; i++) {
      final tensor = reader.vectorElementIndirect(tensorsVector, i);
      // `Tensor.type` is field index 1 (an int8 enum, default FLOAT32 = 0).
      final typeField = reader.fieldPos(tensor, 1);
      final typeCode = typeField == 0
          ? TfliteFlatTensorType.float32
          : reader.i8(typeField);
      final shapeField = reader.fieldPos(tensor, 0);
      final shape = shapeField == 0
          ? const <int>[]
          : reader.intVector(reader.indirect(shapeField));
      final bufferField = reader.fieldPos(tensor, 2);
      final bufferIndex = bufferField == 0 ? 0 : reader.u32(bufferField);

      tensors.add(
        TfliteTensorInfo(
          index: i,
          typeCode: typeCode,
          shape: List<int>.unmodifiable(shape),
          bufferIndex: bufferIndex,
        ),
      );
      counts[typeCode] = (counts[typeCode] ?? 0) + 1;
    }

    return TfliteModelStructure(
      tensors: List<TfliteTensorInfo>.unmodifiable(tensors),
      inputs: reader.intVectorFromField(subgraph, 1),
      outputs: reader.intVectorFromField(subgraph, 2),
      tensorTypeCounts: Map<int, int>.unmodifiable(counts),
    );
  } catch (_) {
    return null;
  }
}

/// Scans the primary subgraph of a TFLite model buffer and returns the number
/// of tensors per flatbuffer `TensorType` code.
///
/// Returns `null` when the buffer cannot be parsed (callers must not guess).
Map<int, int>? scanTfliteTensorTypeCounts(Uint8List modelBytes) {
  return scanTfliteModelStructure(modelBytes)?.tensorTypeCounts;
}

/// ---------------------------------------------------------------------------
/// IEEE-754 half-precision (float16) helpers.
///
/// Used when a model's input/output tensor is FLOAT16: the app pre/post
/// processes in float32 and converts the byte buffer at the run boundary,
/// because the classic runtime copies raw bytes verbatim for ByteBuffer I/O.
/// ---------------------------------------------------------------------------

/// Converts a `Float32List` to little-endian float16 bytes.
Uint8List float32ListToFloat16Bytes(Float32List values) {
  final out = ByteData(values.length * 2);
  for (var i = 0; i < values.length; i++) {
    out.setUint16(
      i * 2,
      _float32BitsToHalf(_float32ToBits(values[i])),
      Endian.little,
    );
  }
  return out.buffer.asUint8List();
}

/// Converts little-endian float16 bytes to a `Float32List`.
Float32List float16BytesToFloat32List(Uint8List bytes) {
  final inData = ByteData.sublistView(bytes);
  final out = Float32List(bytes.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = _halfToFloat32(inData.getUint16(i * 2, Endian.little));
  }
  return out;
}

int _float32ToBits(double value) {
  final bd = ByteData(4)..setFloat32(0, value, Endian.little);
  return bd.getInt32(0, Endian.little);
}

/// IEEE-754 float32 bit pattern → float16 bit pattern (truncating, no rounding).
int _float32BitsToHalf(int bits) {
  final sign = (bits >> 16) & 0x8000;
  final exponent = (bits >> 23) & 0xff;
  final mantissa = bits & 0x7fffff;

  int half;
  if (exponent == 0xff) {
    // Inf / NaN.
    half = (mantissa != 0) ? (sign | 0x7e00) : (sign | 0x7c00);
  } else if (exponent > 142) {
    // Overflow → ±Inf.
    half = sign | 0x7c00;
  } else if (exponent > 112) {
    // Normal float16 (half exponent = 1..30, i.e. 2^-14 .. 2^15).
    half = sign | ((exponent - 112) << 10) | (mantissa >> 13);
  } else if (exponent >= 103) {
    // Subnormal float16 (uses leading mantissa bit).
    // exponent 103 == 2^-24 (smallest half subnormal); 112 == just below 2^-14.
    half = sign | ((mantissa | 0x800000) >> (126 - exponent));
  } else {
    // Underflow → signed zero.
    half = sign;
  }
  return half & 0xffff;
}

/// IEEE-754 float16 bit pattern → double.
double _halfToFloat32(int half) {
  final sign = (half & 0x8000) == 0 ? 1.0 : -1.0;
  final exponent = (half >> 10) & 0x1f;
  final mantissa = half & 0x3ff;

  if (exponent == 0) {
    if (mantissa == 0) return 0.0 * sign; // ±0
    return sign * mantissa * 5.960464477539063e-8; // subnormal: 2^-24
  }
  if (exponent == 0x1f) {
    // Inf (mantissa == 0) or NaN (mantissa != 0).
    return mantissa == 0 ? sign * double.infinity : double.nan;
  }
  return sign *
      (1.0 + mantissa / 1024.0) *
      math.pow(2.0, exponent - 15).toDouble();
}

/// Minimal FlatBuffers reader (tables, vtables, vectors, scalars).
class _FlatBufferReader {
  final ByteData _data;

  _FlatBufferReader(Uint8List bytes) : _data = ByteData.sublistView(bytes);

  int u16(int pos) => _data.getUint16(pos, Endian.little);
  int u32(int pos) => _data.getUint32(pos, Endian.little);
  int i32(int pos) => _data.getInt32(pos, Endian.little);
  int i8(int pos) => _data.getInt8(pos);

  /// Resolves a relative offset stored at [pos] (uoffset relative to [pos]).
  int indirect(int pos) => pos + u32(pos);

  int _vtableBase(int tablePos) => tablePos - i32(tablePos);

  int _vtableSize(int vtablePos) => u16(vtablePos);

  /// Offset of [fieldIndex] within [tablePos]'s vtable, or 0 if absent.
  ///
  /// Vtable layout: [vtableSize u16][tableSize u16][field0 u16][field1 u16]…
  int fieldOffset(int tablePos, int fieldIndex) {
    final vtable = _vtableBase(tablePos);
    final slot = 4 + fieldIndex * 2;
    if (slot >= _vtableSize(vtable)) return 0;
    return u16(vtable + slot);
  }

  /// Absolute position of [fieldIndex]'s data within [tablePos], or 0.
  int fieldPos(int tablePos, int fieldIndex) {
    final offset = fieldOffset(tablePos, fieldIndex);
    return offset == 0 ? 0 : tablePos + offset;
  }

  int vectorLength(int vectorPos) => u32(vectorPos);

  List<int> intVector(int vectorPos) {
    final length = vectorLength(vectorPos);
    return [
      for (var i = 0; i < length; i++)
        _data.getInt32(vectorPos + 4 + i * 4, Endian.little),
    ];
  }

  List<int> intVectorFromField(int tablePos, int fieldIndex) {
    final field = fieldPos(tablePos, fieldIndex);
    return field == 0 ? const <int>[] : intVector(indirect(field));
  }

  /// Resolves the [index]-th element of a vector of table offsets.
  int vectorElementIndirect(int vectorPos, int index) {
    final elementPos = vectorPos + 4 + index * 4;
    return elementPos + u32(elementPos);
  }
}
