import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../models/detector_model.dart';
import '../models/model_config.dart';
import '../models/tflite_flatbuffer.dart';
import 'settings_service.dart';

/// Largest model file the import pipeline accepts (and the largest the Android
/// picker copies out of the document provider).
const int kMaxImportBytes = 40 * 1024 * 1024;

/// Largest number of class labels accepted from model metadata.
const int kMaxImportLabels = 1000;

/// Platform seam for the system document picker.
abstract class ModelFilePicker {
  /// Returns a readable **temporary** local copy of the chosen `.tflite` file,
  /// or `null` when the researcher cancelled.
  Future<String?> pickTflite();
}

/// App-local picker channel (`android/app/src/main/kotlin/.../MainActivity.kt`).
///
/// Deliberately not a plugin: no dependency, nothing to re-sync, and the copied
/// path is app cache the picker itself owns.
class PlatformModelFilePicker implements ModelFilePicker {
  static const MethodChannel channel = MethodChannel('eyecue/model_picker');

  const PlatformModelFilePicker();

  @override
  Future<String?> pickTflite() async {
    final path = await channel.invokeMethod<String>('pickTflite');
    return path == null || path.isEmpty ? null : path;
  }
}

/// Outcome of one import attempt.
class ModelImportResult {
  final DetectorModel? model;

  /// User-facing, actionable text. Never contains paths or exception text.
  final String? message;

  const ModelImportResult._({this.model, this.message});

  const ModelImportResult.success(DetectorModel model) : this._(model: model);

  const ModelImportResult.failure(String message) : this._(message: message);

  const ModelImportResult.cancelled() : this._();

  bool get ok => model != null;

  bool get wasCancelled => model == null && message == null;
}

/// Owns the detector selection and the import pipeline
/// (validate → stage → commit).
///
/// Only one custom copy is ever kept: the imported graph plus its label
/// sidecar, both named by content fingerprint so the native filename/size
/// model caches cannot reuse a stale graph. The copy outlives a switch to the
/// built-in detector, so the last import stays re-selectable; a successful
/// replacement import is what removes the previous copy.
class DetectorModelService extends ChangeNotifier {
  DetectorModelService(
    this._settings, {
    ModelFilePicker? picker,
    Future<List<String>> Function()? builtInLabelsLoader,
    Future<Map<String, dynamic>> Function(String path)? inspect,
    Future<Directory> Function()? modelsDirectory,
  }) : _picker = picker ?? const PlatformModelFilePicker(),
       _loadBuiltInLabels = builtInLabelsLoader ?? _defaultBuiltInLabels,
       _inspect = inspect ?? _defaultInspect,
       _modelsDirectory = modelsDirectory ?? _defaultModelsDirectory;

  final SettingsService _settings;
  final ModelFilePicker _picker;
  final Future<List<String>> Function() _loadBuiltInLabels;
  final Future<Map<String, dynamic>> Function(String path) _inspect;
  final Future<Directory> Function() _modelsDirectory;

  DetectorModel _builtIn = DetectorModel.builtIn(const []);
  DetectorModel _current = DetectorModel.builtIn(const []);
  String? _selectionRecoveryMessage;

  /// Active selection. Built-in (with empty labels) until [load] completes.
  DetectorModel get current => _current;

  DetectorModel get builtIn => _builtIn;

  bool get isCustomSelected => _current.isCustom;

  /// Non-null when the persisted custom selection could not be restored. The
  /// caller must surface it; recovery is never silent.
  String? get selectionRecoveryMessage => _selectionRecoveryMessage;

  String get _unavailableMessage =>
      'The imported custom model is no longer available, so '
      '${_builtIn.displayName} is selected. Import the model again to use it.';

  /// Reads the persisted selection and repairs an unusable one.
  ///
  /// An older settings file, or a custom selection whose app-owned copy or
  /// sidecar is gone, resolves to the built-in detector — never to a model the
  /// app cannot actually load.
  Future<void> load() async {
    _builtIn = DetectorModel.builtIn(await _loadBuiltInLabels());
    _selectionRecoveryMessage = null;

    if (_settings.detectorModelKind != DetectorModelKind.custom) {
      _current = _builtIn;
      notifyListeners();
      return;
    }

    final restored = await _restoreCustom();
    if (restored != null) {
      _current = restored;
    } else {
      _current = _builtIn;
      _selectionRecoveryMessage = _unavailableMessage;
      // The copy is gone or no longer matches its name: drop the identity too,
      // otherwise the next start would retry the same broken selection.
      await _settings.setDetectorModel(
        kind: DetectorModelKind.builtIn,
        clearCustomModel: true,
      );
    }
    notifyListeners();
  }

  /// Switches back to the bundled detector. The app-owned custom copy and its
  /// identity are kept, so [selectStoredCustom] can restore the last valid
  /// import without repeating it. The bundled asset is never touched.
  Future<void> selectBuiltIn() async {
    await _settings.setDetectorModel(kind: DetectorModelKind.builtIn);
    _current = _builtIn;
    _selectionRecoveryMessage = null;
    notifyListeners();
  }

  /// Re-selects the stored custom model without importing it again.
  ///
  /// Verifies the app-owned copy and its fingerprint before selecting, so a
  /// missing or corrupted file cannot be presented as the active model.
  Future<ModelImportResult> selectStoredCustom() async {
    final restored = await _restoreCustom();
    if (restored == null) {
      _current = _builtIn;
      _selectionRecoveryMessage = _unavailableMessage;
      notifyListeners();
      await _settings.setDetectorModel(
        kind: DetectorModelKind.builtIn,
        clearCustomModel: true,
      );
      return ModelImportResult.failure(_unavailableMessage);
    }
    await _settings.setDetectorModel(
      kind: DetectorModelKind.custom,
      name: restored.displayName,
      fingerprint: restored.fingerprint,
      classCount: restored.classCount,
    );
    _current = restored;
    _selectionRecoveryMessage = null;
    notifyListeners();
    return ModelImportResult.success(restored);
  }

  /// Opens the system picker, then imports the chosen file.
  ///
  /// A cancelled picker changes nothing. The picker's temporary copy is always
  /// removed; the researcher's original document is never modified.
  Future<ModelImportResult> importFromPicker({
    required String displayName,
  }) async {
    String? picked;
    try {
      picked = await _picker.pickTflite();
    } on PlatformException {
      return const ModelImportResult.failure(_genericFailure);
    } on Exception {
      return const ModelImportResult.failure(_genericFailure);
    }
    if (picked == null) return const ModelImportResult.cancelled();
    try {
      return await importFromPath(picked, displayName: displayName);
    } finally {
      await _deleteQuietly(File(picked));
    }
  }

  /// Validates [path] and, only if every check passes, commits it as the
  /// selection. Any failure leaves the previous selection untouched.
  Future<ModelImportResult> importFromPath(
    String path, {
    required String displayName,
  }) async {
    final name = displayName.trim();
    final nameError = _validateDisplayName(name);
    if (nameError != null) return ModelImportResult.failure(nameError);

    File? staged;
    try {
      final source = File(path);
      final size = await source.length();
      if (size <= 0) {
        return const ModelImportResult.failure(
          'That file is empty. Choose an exported YOLO .tflite model.',
        );
      }
      if (size > kMaxImportBytes) {
        return const ModelImportResult.failure(
          'That model is larger than 40 MB. Use a smaller exported model.',
        );
      }

      final bytes = await source.readAsBytes();
      final structure = scanTfliteModelStructure(bytes);
      if (structure == null) {
        return const ModelImportResult.failure(
          'That file is not a readable TFLite model. Choose a .tflite model '
          'exported from Ultralytics YOLO.',
        );
      }

      final info = await _inspect(path);
      final task = info['task'];
      final channelCandidates = _channelCandidates(structure);
      if (task is String && task.isNotEmpty && task != 'detect') {
        return ModelImportResult.failure(
          'That model is for "$task", not object detection. Export a '
          'detection model, then import it again.',
        );
      }
      if ((task is! String || task.isEmpty) && channelCandidates.isEmpty) {
        return const ModelImportResult.failure(
          'That model does not look like an object-detection model. Export a '
          'YOLO detection model with its labels embedded.',
        );
      }

      final labels = _parseLabels(info['labels']);
      if (labels == null) {
        return const ModelImportResult.failure(
          'That model has no usable class labels. Re-export it from '
          'Ultralytics YOLO with labels embedded in the model metadata.',
        );
      }
      final mismatch = labelShapeMismatch(structure, labels.length);
      if (mismatch != null) return ModelImportResult.failure(mismatch);

      final directory = await _modelsDirectory();
      await directory.create(recursive: true);
      final fingerprint = tfliteFingerprint(bytes);

      staged = File('${directory.path}/.staging-$fingerprint.tflite');
      await staged.writeAsBytes(bytes, flush: true);
      final target = _modelFile(directory, fingerprint);
      await staged.rename(target.path);
      staged = null;

      await _sidecarFile(directory, fingerprint).writeAsString(
        jsonEncode({
          'displayName': name,
          'fingerprint': fingerprint,
          'classCount': labels.length,
          'labels': labels,
          'bytes': bytes.length,
        }),
        flush: true,
      );

      final previous = _current;
      final model = DetectorModel(
        kind: DetectorModelKind.custom,
        displayName: name,
        fingerprint: fingerprint,
        labels: List<String>.unmodifiable(labels),
        fileSizeBytes: bytes.length,
        path: target.path,
      );
      await _settings.setDetectorModel(
        kind: DetectorModelKind.custom,
        name: name,
        fingerprint: fingerprint,
        classCount: labels.length,
      );
      _current = model;
      _selectionRecoveryMessage = null;
      notifyListeners();

      // Only a committed replacement import drops the previous copy.
      if (previous.isCustom && previous.fingerprint != fingerprint) {
        await _deleteAppOwned(previous.fingerprint);
      }
      return ModelImportResult.success(model);
    } on FileSystemException {
      return const ModelImportResult.failure(_genericFailure);
    } on MissingPluginException {
      // No native inspector channel (unsupported host/ABI): fail visibly
      // instead of surfacing an unhandled async error.
      return const ModelImportResult.failure(_genericFailure);
    } on PlatformException {
      return const ModelImportResult.failure(_genericFailure);
    } finally {
      final leftover = staged;
      if (leftover != null) await _deleteQuietly(leftover);
    }
  }

  /// File names the service owns in its models directory (tests + diagnostics).
  Future<List<String>> debugStoredFiles() async {
    final directory = await _modelsDirectory();
    if (!await directory.exists()) return const [];
    final names = directory
        .listSync()
        .map((entity) => entity.path.split(Platform.pathSeparator).last)
        .toList();
    names.sort();
    return names;
  }

  static const String _genericFailure =
      'That model could not be imported. Choose another exported YOLO .tflite '
      'model and try again.';

  /// Short, non-identifying researcher name for the imported graph.
  static String? _validateDisplayName(String name) {
    if (name.isEmpty) {
      return 'Enter a short model name, such as Obstacle Detector v2.';
    }
    if (name.length > 40) {
      return 'Keep the model name to 40 characters or fewer.';
    }
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9 ._/-]*$').hasMatch(name)) {
      return 'Use letters, numbers, spaces, and . _ - only, and do not use '
          'respondent names or email addresses.';
    }
    return null;
  }

  Future<DetectorModel?> _restoreCustom() async {
    final fingerprint = _settings.customModelFingerprint;
    final name = _settings.customModelName;
    final classCount = _settings.customModelClassCount;
    if (fingerprint == null || name == null || classCount == null) {
      return null;
    }
    try {
      final directory = await _modelsDirectory();
      final file = _modelFile(directory, fingerprint);
      if (!await file.exists()) return null;
      final sidecar = await _readSidecar(directory, fingerprint);
      if (sidecar == null || sidecar['fingerprint'] != fingerprint) return null;
      final size = await file.length();
      if (sidecar['bytes'] != size) return null;
      // Length alone cannot catch a same-size corruption, so re-derive the
      // identity from the bytes. A mismatch makes the app-owned copy useless:
      // remove it so the next import starts clean and the name is not reused.
      if (await _fileFingerprint(file) != fingerprint) {
        await _deleteAppOwned(fingerprint);
        return null;
      }
      final labels = _parseLabels(sidecar['labels']);
      if (labels == null || labels.length != classCount) return null;
      return DetectorModel(
        kind: DetectorModelKind.custom,
        displayName: name,
        fingerprint: fingerprint,
        labels: List<String>.unmodifiable(labels),
        fileSizeBytes: size,
        path: file.path,
      );
    } on FileSystemException {
      return null;
    }
  }

  /// Both app-owned files are named by fingerprint, so the path never needs to
  /// be persisted (and so never reaches exported settings).
  static File _modelFile(Directory directory, String fingerprint) =>
      File('${directory.path}/$fingerprint.tflite');

  static File _sidecarFile(Directory directory, String fingerprint) =>
      File('${directory.path}/$fingerprint.labels.json');

  /// Re-hashes the committed copy in chunks: a 40 MB model must not be loaded
  /// into memory a second time just to verify it.
  static Future<String?> _fileFingerprint(File file) async {
    final accumulator = TfliteFingerprintAccumulator();
    try {
      await for (final chunk in file.openRead()) {
        accumulator.add(chunk);
      }
    } on FileSystemException {
      return null;
    }
    return accumulator.fingerprint;
  }

  Future<Map<String, dynamic>?> _readSidecar(
    Directory directory,
    String fingerprint,
  ) async {
    try {
      final file = _sidecarFile(directory, fingerprint);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Trims labels and rejects anything unusable instead of guessing.
  static List<String>? _parseLabels(Object? raw) {
    if (raw is! List || raw.isEmpty || raw.length > kMaxImportLabels) {
      return null;
    }
    final labels = <String>[];
    for (final item in raw) {
      if (item is! String) return null;
      final label = item.trim();
      if (label.isEmpty || label.length > 64) return null;
      labels.add(label);
    }
    return labels;
  }

  /// Every output dimension that can be a YOLO channel count (`4 + classCount`),
  /// i.e. `5 <= d <= kMaxImportLabels + 4`.
  ///
  /// Shapes are `[1, 4 + n, anchors]` or `[1, anchors, 4 + n]` — and a
  /// small-anchor export can have both in range (`[1, 84, 300]`), so the whole
  /// set is kept rather than guessing which one is the channel axis.
  static List<int> _channelCandidates(TfliteModelStructure structure) {
    final found = <int>{};
    for (final tensor in structure.outputTensors) {
      for (final dimension in tensor.shape) {
        if (dimension >= 5 && dimension <= kMaxImportLabels + 4) {
          found.add(dimension);
        }
      }
    }
    return found.toList()..sort();
  }

  /// Non-null when the detection head cannot carry [labelCount] classes.
  ///
  /// One matching candidate is enough (the other in-range dimension is the
  /// anchor/detection count). Candidates that all disagree mean the labels are
  /// not this graph's labels — accepting them would silently mislabel every
  /// detection. Only a shape with no candidate at all is left without an
  /// opinion.
  @visibleForTesting
  static String? labelShapeMismatch(
    TfliteModelStructure structure,
    int labelCount,
  ) {
    final candidates = _channelCandidates(structure);
    if (candidates.isEmpty) return null;
    if (candidates.contains(labelCount + 4)) return null;
    return 'That model reports $labelCount labels but its output does not '
        'match them. Re-export the model with its own labels embedded.';
  }

  Future<void> _deleteAppOwned(String fingerprint) async {
    try {
      final directory = await _modelsDirectory();
      await _deleteQuietly(_modelFile(directory, fingerprint));
      await _deleteQuietly(_sidecarFile(directory, fingerprint));
    } on FileSystemException {
      // A leftover copy is harmless: the next import rewrites by fingerprint.
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Cleanup is best-effort; a stale staging file is never a selection.
    }
  }

  static Future<Map<String, dynamic>> _defaultInspect(String path) =>
      YOLO.inspectModel(path);

  static Future<Directory> _defaultModelsDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/eyecue_models');
  }

  static Future<List<String>> _defaultBuiltInLabels() async {
    try {
      final text = await rootBundle.loadString(
        EyeCueModelConfig.labelsAssetPath,
      );
      return text
          .split('\n')
          .map((label) => label.trim())
          .where((label) => label.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      // The bundled label list is a compile-time asset; an empty result keeps
      // startup alive and is visible as a zero class count.
      return const [];
    }
  }
}
