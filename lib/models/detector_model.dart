import 'dart:typed_data';

import '../services/spatial_analysis_service.dart';
import 'detection_info.dart';
import 'model_config.dart';

/// Which detector graph produced a result.
enum DetectorModelKind { builtIn, custom }

/// Compact, per-record identity of a detector graph.
///
/// Carries the readable name captured when the record was written, so renaming
/// or switching models later cannot relabel history.
class DetectorModelRef {
  final String id;
  final String name;
  final String fingerprint;
  final int classCount;

  const DetectorModelRef({
    required this.id,
    required this.name,
    required this.fingerprint,
    required this.classCount,
  });

  @override
  bool operator ==(Object other) =>
      other is DetectorModelRef &&
      other.id == id &&
      other.name == name &&
      other.fingerprint == fingerprint &&
      other.classCount == classCount;

  @override
  int get hashCode => Object.hash(id, name, fingerprint, classCount);

  @override
  String toString() => 'DetectorModelRef($id, $name, $classCount classes)';
}

/// An immutable detector selection: the bundled YOLOv8n or one imported graph.
class DetectorModel {
  final DetectorModelKind kind;
  final String displayName;

  /// Content-derived identity of the graph (see [tfliteFingerprint]) or the
  /// fixed built-in marker.
  final String fingerprint;
  final List<String> labels;
  final int fileSizeBytes;

  /// Asset path for the built-in model, absolute path of the app-owned copy for
  /// a custom model.
  final String path;

  const DetectorModel({
    required this.kind,
    required this.displayName,
    required this.fingerprint,
    required this.labels,
    required this.fileSizeBytes,
    required this.path,
  });

  /// The bundled detector. Behavior and COCO label order stay untouched.
  factory DetectorModel.builtIn(List<String> cocoLabels) => DetectorModel(
    kind: DetectorModelKind.builtIn,
    displayName: 'Built-in YOLOv8n',
    fingerprint: builtInFingerprint,
    labels: List<String>.unmodifiable(cocoLabels),
    fileSizeBytes: 0,
    path: EyeCueModelConfig.modelAssetPath,
  );

  static const String builtInFingerprint = 'builtin-yolov8n-int8-metadata';

  bool get isCustom => kind == DetectorModelKind.custom;

  int get classCount => labels.length;

  /// `'builtin'` or `'custom:<first 12 hex chars>'`.
  String get id {
    if (!isCustom) return 'builtin';
    final hex = fingerprint.split('-').first;
    return 'custom:${hex.length > 12 ? hex.substring(0, 12) : hex}';
  }

  DetectorModelRef get ref => DetectorModelRef(
    id: id,
    name: displayName,
    fingerprint: fingerprint,
    classCount: classCount,
  );

  @override
  String toString() => 'DetectorModel($id, $displayName, $classCount classes)';
}

/// FNV-1a 64-bit over [bytes] as 16 lowercase hex chars plus `-<byteLength>`.
///
/// Non-cryptographic: it distinguishes graph contents, so the native filename
/// based model/GPU caches cannot reuse a stale graph. It is not a security
/// primitive and not a substitute for a cryptographic digest.
String tfliteFingerprint(Uint8List bytes) =>
    (TfliteFingerprintAccumulator()..add(bytes)).fingerprint;

/// Incremental [tfliteFingerprint], so an already committed model can be
/// re-hashed in chunks instead of being loaded twice into memory.
class TfliteFingerprintAccumulator {
  int _hash = 0xcbf29ce484222325;
  int _length = 0;

  void add(List<int> bytes) {
    var hash = _hash;
    for (final byte in bytes) {
      hash = (hash ^ byte) * 0x100000001b3;
    }
    _hash = hash;
    _length += bytes.length;
  }

  /// Same string [tfliteFingerprint] returns for the concatenated chunks.
  String get fingerprint {
    final high = (_hash >> 32) & 0xFFFFFFFF;
    final low = _hash & 0xFFFFFFFF;
    final hex =
        '${high.toRadixString(16).padLeft(8, '0')}'
        '${low.toRadixString(16).padLeft(8, '0')}';
    return '$hex-$_length';
  }
}

/// Narrow, semantic name sets used only for **custom** model labels.
///
/// These are plain hazard-category names, not a COCO class-id table: a custom
/// model's class `0` means whatever its own metadata says.
const Set<String> customHighPriorityLabels = {
  'person',
  'people',
  'human',
  'pedestrian',
  'car',
  'bus',
  'truck',
  'motorcycle',
  'bicycle',
  'bike',
  'train',
  'traffic light',
  'stop sign',
};

/// Narrow, semantic medium-hazard names (large static obstacles plus the
/// everyday objects the built-in detector already ranks medium).
const Set<String> customMediumPriorityLabels = {
  'chair',
  'table',
  'dining table',
  'bench',
  'door',
  'stairs',
  'steps',
  'staircase',
  'wall',
  'pole',
  'cone',
  'box',
  'backpack',
  'suitcase',
  'bird',
  'cat',
  'dog',
  'horse',
  'sheep',
  'cow',
  'elephant',
  'sports ball',
  'skateboard',
  'bottle',
  'wine glass',
  'cup',
  'bowl',
  'banana',
  'orange',
  'pizza',
  'couch',
  'potted plant',
  'tv',
  'laptop',
  'cell phone',
  'oven',
  'toaster',
  'sink',
  'refrigerator',
  'book',
  'clock',
  'vase',
};

/// Priority for a detection from [kind].
///
/// The built-in model keeps its existing COCO class-id policy unchanged. A
/// custom model is judged **only** by its own label text — never by [classId],
/// so a custom class `0` cannot inherit COCO person priority.
ObjectPriority priorityForClass(
  DetectorModelKind kind,
  int classId,
  String label,
) {
  if (kind == DetectorModelKind.builtIn) {
    return SpatialAnalysisService.priorityFor(classId);
  }
  final normalized = normalizeLabelName(label);
  if (customHighPriorityLabels.contains(normalized)) return ObjectPriority.high;
  if (customMediumPriorityLabels.contains(normalized)) {
    return ObjectPriority.medium;
  }
  return ObjectPriority.low;
}

/// Lowercase, `_`/`-` folded, whitespace-collapsed label text.
///
/// Ultralytics metadata commonly exports `traffic_light`; the semantic sets
/// above are written in plain words.
String normalizeLabelName(String label) => label
    .toLowerCase()
    .replaceAll(RegExp(r'[_-]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
