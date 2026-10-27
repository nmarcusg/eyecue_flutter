import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:eyecue_flutter/models/detector_model.dart';
import 'package:eyecue_flutter/models/tflite_flatbuffer.dart';
import 'package:eyecue_flutter/services/detector_model_service.dart';
import 'package:eyecue_flutter/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bundled graph is the only fixture with a real flatbuffer; the scanner
/// accepts appended bytes, so `asset + [..]` is a distinct, still-valid graph.
const String _assetPath = 'assets/yolov8n_int8_new_metadata.tflite';
const int _cocoClassCount = 80;

late Uint8List _modelBytes;

Future<Map<String, dynamic>> _detectInspect(String path) async => {
  'task': 'detect',
  'labels': List<String>.generate(_cocoClassCount, (index) => 'class$index'),
};

class _FakePicker implements ModelFilePicker {
  _FakePicker(this.path);

  final String? path;
  int calls = 0;

  @override
  Future<String?> pickTflite() async {
    calls++;
    return path;
  }
}

void main() {
  late Directory tempDir;
  late InMemorySettingsStore store;
  late SettingsService settings;

  Directory modelsDirectory() => Directory('${tempDir.path}/eyecue_models');

  DetectorModelService buildService({
    ModelFilePicker? picker,
    Future<Map<String, dynamic>> Function(String path)? inspect,
  }) => DetectorModelService(
    settings,
    picker: picker ?? _FakePicker(null),
    builtInLabelsLoader: () async =>
        List<String>.generate(_cocoClassCount, (index) => 'class$index'),
    inspect: inspect ?? _detectInspect,
    modelsDirectory: () async => modelsDirectory(),
  );

  String writeSource(String name, List<int> bytes) {
    final file = File('${tempDir.path}/$name')..writeAsBytesSync(bytes);
    return file.path;
  }

  setUpAll(() {
    _modelBytes = File(_assetPath).readAsBytesSync();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('eyecue_model_test');
    store = InMemorySettingsStore();
    settings = SettingsService(store: store);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('selection recovery', () {
    test(
      'legacy settings without detector fields select the built-in model',
      () async {
        store.contents = jsonEncode({
          'schemaVersion': 6,
          'vibrationFeedback': false,
        });
        await settings.load();

        final service = buildService();
        await service.load();

        expect(service.isCustomSelected, isFalse);
        expect(service.current.kind, DetectorModelKind.builtIn);
        expect(service.current.displayName, 'Built-in YOLOv8n');
        expect(service.current.ref.classCount, _cocoClassCount);
        expect(service.selectionRecoveryMessage, isNull);
      },
    );

    test('a persisted selection survives a reload', () async {
      final first = buildService();
      await first.load();
      final result = await first.importFromPath(
        writeSource('model.tflite', _modelBytes),
        displayName: 'Obstacle Detector v2',
      );
      expect(result.ok, isTrue);
      final imported = result.model!;

      final reloadedSettings = SettingsService(store: store);
      await reloadedSettings.load();
      settings = reloadedSettings;
      final service = buildService();
      await service.load();

      expect(service.isCustomSelected, isTrue);
      expect(service.current.fingerprint, imported.fingerprint);
      expect(service.current.displayName, 'Obstacle Detector v2');
      expect(service.current.ref.classCount, _cocoClassCount);
      expect(service.selectionRecoveryMessage, isNull);
    });

    test(
      'a deleted custom copy recovers to built-in with a visible message',
      () async {
        final first = buildService();
        await first.load();
        final result = await first.importFromPath(
          writeSource('model.tflite', _modelBytes),
          displayName: 'Obstacle Detector v2',
        );
        expect(result.ok, isTrue);
        File(result.model!.path).deleteSync();

        final service = buildService();
        await service.load();

        expect(service.isCustomSelected, isFalse);
        expect(service.current.displayName, 'Built-in YOLOv8n');
        expect(service.selectionRecoveryMessage, isNotNull);
        expect(
          service.selectionRecoveryMessage,
          contains('no longer available'),
        );
      },
    );

    test(
      'a same-length corrupted copy recovers to built-in and is removed',
      () async {
        final first = buildService();
        await first.load();
        final result = await first.importFromPath(
          writeSource('model.tflite', _modelBytes),
          displayName: 'Obstacle Detector v2',
        );
        expect(result.ok, isTrue);
        final path = result.model!.path;

        final tampered = Uint8List.fromList(File(path).readAsBytesSync());
        tampered[tampered.length ~/ 2] ^= 0xff;
        File(path).writeAsBytesSync(tampered);
        expect(tampered.length, result.model!.fileSizeBytes);

        final service = buildService();
        await service.load();

        expect(service.isCustomSelected, isFalse);
        expect(service.current.displayName, 'Built-in YOLOv8n');
        expect(service.selectionRecoveryMessage, isNotNull);
        expect(File(path).existsSync(), isFalse);
        expect(settings.customModelFingerprint, isNull);
        expect(await service.debugStoredFiles(), isEmpty);
      },
    );
  });

  group('import', () {
    test('picker cancellation changes nothing', () async {
      final picker = _FakePicker(null);
      final service = buildService(picker: picker);
      await service.load();

      final result = await service.importFromPicker(
        displayName: 'Obstacle Detector v2',
      );

      expect(picker.calls, 1);
      expect(result.wasCancelled, isTrue);
      expect(result.ok, isFalse);
      expect(service.isCustomSelected, isFalse);
      expect(modelsDirectory().existsSync(), isFalse);
    });

    test('a non-TFLite file fails and leaves no file behind', () async {
      final service = buildService();
      await service.load();

      final result = await service.importFromPath(
        writeSource('bogus.tflite', utf8.encode('this is not a flatbuffer')),
        displayName: 'Obstacle Detector v2',
      );

      expect(result.ok, isFalse);
      expect(result.message, contains('not a readable TFLite model'));
      expect(service.isCustomSelected, isFalse);
      expect(await service.debugStoredFiles(), isEmpty);
    });

    test('a wrong-task model fails with an actionable message', () async {
      final service = buildService(
        inspect: (path) async => {
          'task': 'classify',
          'labels': const ['cat', 'dog'],
        },
      );
      await service.load();

      final result = await service.importFromPath(
        writeSource('model.tflite', _modelBytes),
        displayName: 'Obstacle Detector v2',
      );

      expect(result.ok, isFalse);
      expect(result.message, contains('not object detection'));
      expect(service.isCustomSelected, isFalse);
      expect(await service.debugStoredFiles(), isEmpty);
    });

    test('labels that contradict the output classes fail', () async {
      final service = buildService(
        inspect: (path) async => {
          'task': 'detect',
          'labels': const ['a', 'b', 'c', 'd', 'e'],
        },
      );
      await service.load();

      final result = await service.importFromPath(
        writeSource('model.tflite', _modelBytes),
        displayName: 'Obstacle Detector v2',
      );

      expect(result.ok, isFalse);
      expect(result.message, contains('5 labels'));
      expect(service.isCustomSelected, isFalse);
      expect(await service.debugStoredFiles(), isEmpty);
    });

    test('a model without labels fails instead of guessing them', () async {
      final service = buildService(inspect: (path) async => {'task': 'detect'});
      await service.load();

      final result = await service.importFromPath(
        writeSource('model.tflite', _modelBytes),
        displayName: 'Obstacle Detector v2',
      );

      expect(result.ok, isFalse);
      expect(result.message, contains('no usable class labels'));
    });

    test('an identifying model name is rejected', () async {
      final service = buildService();
      await service.load();

      final result = await service.importFromPath(
        writeSource('model.tflite', _modelBytes),
        displayName: 'juan@example.com',
      );

      expect(result.ok, isFalse);
      expect(result.message, contains('respondent names'));
      expect(await service.debugStoredFiles(), isEmpty);
    });

    test(
      'a successful import stores a content-named copy and sidecar',
      () async {
        final service = buildService();
        await service.load();

        final result = await service.importFromPath(
          writeSource('model.tflite', _modelBytes),
          displayName: 'Obstacle Detector v2',
        );

        expect(result.ok, isTrue);
        final model = result.model!;
        final fingerprint = tfliteFingerprint(_modelBytes);
        final expected = File('${modelsDirectory().path}/$fingerprint.tflite');

        expect(model.fingerprint, fingerprint);
        expect(model.path, expected.path);
        expect(expected.existsSync(), isTrue);
        expect(model.fileSizeBytes, _modelBytes.length);

        final sidecar =
            jsonDecode(
                  File(
                    '${modelsDirectory().path}/$fingerprint.labels.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        expect(sidecar['displayName'], 'Obstacle Detector v2');
        expect(sidecar['fingerprint'], fingerprint);
        expect(sidecar['classCount'], _cocoClassCount);
        expect((sidecar['labels'] as List).length, _cocoClassCount);
        expect(sidecar['bytes'], _modelBytes.length);

        expect(settings.detectorModelKind, DetectorModelKind.custom);
        expect(settings.customModelFingerprint, fingerprint);
        expect(settings.customModelClassCount, _cocoClassCount);

        expect(service.current.ref.name, 'Obstacle Detector v2');
        expect(service.current.ref.classCount, _cocoClassCount);
        expect(
          service.current.ref.id,
          'custom:${fingerprint.split('-').first.substring(0, 12)}',
        );
        expect(await service.debugStoredFiles(), hasLength(2));
      },
    );

    test('a replacement import deletes the previous app-owned copy', () async {
      final service = buildService();
      await service.load();
      final first = await service.importFromPath(
        writeSource('first.tflite', _modelBytes),
        displayName: 'First model',
      );
      expect(first.ok, isTrue);
      final firstPath = first.model!.path;

      final replacementBytes = Uint8List.fromList([..._modelBytes, 1, 2, 3]);
      final second = await service.importFromPath(
        writeSource('second.tflite', replacementBytes),
        displayName: 'Second model',
      );

      expect(second.ok, isTrue);
      expect(second.model!.fingerprint, isNot(first.model!.fingerprint));
      expect(File(firstPath).existsSync(), isFalse);
      expect(File(second.model!.path).existsSync(), isTrue);
      expect(
        File(firstPath.replaceAll('.tflite', '.labels.json')).existsSync(),
        isFalse,
      );
      expect(await service.debugStoredFiles(), hasLength(2));
      expect(settings.customModelFingerprint, second.model!.fingerprint);
      expect(service.current.displayName, 'Second model');
    });

    test(
      'switching to built-in keeps the copy so it can be re-selected',
      () async {
        final service = buildService();
        await service.load();
        final imported = await service.importFromPath(
          writeSource('model.tflite', _modelBytes),
          displayName: 'Obstacle Detector v2',
        );
        expect(imported.ok, isTrue);
        final first = imported.model!;

        await service.selectBuiltIn();

        expect(service.isCustomSelected, isFalse);
        expect(File(first.path).existsSync(), isTrue);
        expect(settings.detectorModelKind, DetectorModelKind.builtIn);
        // The identity is retained, only the selection changed.
        expect(settings.customModelFingerprint, first.fingerprint);
        expect(settings.customModelName, 'Obstacle Detector v2');
        expect(await service.debugStoredFiles(), hasLength(2));

        final reselected = await service.selectStoredCustom();

        expect(reselected.ok, isTrue);
        expect(reselected.model!.fingerprint, first.fingerprint);
        expect(reselected.model!.ref.id, first.ref.id);
        expect(reselected.model!.displayName, 'Obstacle Detector v2');
        expect(reselected.model!.ref.classCount, _cocoClassCount);
        expect(service.isCustomSelected, isTrue);
        expect(service.selectionRecoveryMessage, isNull);
        expect(settings.detectorModelKind, DetectorModelKind.custom);
        expect(await service.debugStoredFiles(), hasLength(2));

        // built-in → custom → built-in repeatedly in one app run.
        await service.selectBuiltIn();
        await service.selectBuiltIn();
        expect((await service.selectStoredCustom()).ok, isTrue);
        expect(await service.debugStoredFiles(), hasLength(2));
      },
    );

    test('re-selecting a removed copy recovers to built-in visibly', () async {
      final service = buildService();
      await service.load();
      final imported = await service.importFromPath(
        writeSource('model.tflite', _modelBytes),
        displayName: 'Obstacle Detector v2',
      );
      expect(imported.ok, isTrue);
      await service.selectBuiltIn();
      File(imported.model!.path).deleteSync();

      final reselected = await service.selectStoredCustom();

      expect(reselected.ok, isFalse);
      expect(reselected.message, contains('Import the model again'));
      expect(service.isCustomSelected, isFalse);
      expect(service.selectionRecoveryMessage, isNotNull);
      expect(settings.detectorModelKind, DetectorModelKind.builtIn);
      expect(settings.customModelFingerprint, isNull);
    });

    test('a valid custom selection survives an invalid import', () async {
      var task = 'detect';
      final service = buildService(
        inspect: (path) async => {
          'task': task,
          'labels': List<String>.generate(
            _cocoClassCount,
            (index) => 'class$index',
          ),
        },
      );
      await service.load();
      final imported = await service.importFromPath(
        writeSource('model.tflite', _modelBytes),
        displayName: 'Obstacle Detector v2',
      );
      expect(imported.ok, isTrue);
      final kept = imported.model!;

      // (a) truncated file, (b) wrong-task file — both from a valid selection.
      final truncated = _modelBytes.sublist(0, 16);
      final truncatedResult = await service.importFromPath(
        writeSource('truncated.tflite', truncated),
        displayName: 'Replacement',
      );
      task = 'classify';
      final wrongTaskResult = await service.importFromPath(
        writeSource('classifier.tflite', _modelBytes),
        displayName: 'Replacement',
      );

      expect(truncatedResult.ok, isFalse);
      expect(wrongTaskResult.ok, isFalse);
      expect(service.current.fingerprint, kept.fingerprint);
      expect(service.current.displayName, 'Obstacle Detector v2');
      expect(settings.customModelFingerprint, kept.fingerprint);
      expect(File(kept.path).existsSync(), isTrue);
      expect(await service.debugStoredFiles(), hasLength(2));

      final reselected = await service.selectStoredCustom();
      expect(reselected.ok, isTrue);
      expect(reselected.model!.fingerprint, kept.fingerprint);
    });
  });

  group('label/class agreement', () {
    TfliteModelStructure shape(List<int> output) => TfliteModelStructure(
      tensors: [
        TfliteTensorInfo(
          index: 0,
          typeCode: TfliteFlatTensorType.float32,
          shape: output,
          bufferIndex: 0,
        ),
      ],
      inputs: const [0],
      outputs: const [0],
      tensorTypeCounts: const {},
    );

    test('an ambiguous channel pair still has to match the labels', () {
      // [1, 84, 300]: 84 and 300 are both in the candidate range. 3 labels
      // need 7 channels, so neither can be the class axis.
      final mismatch = DetectorModelService.labelShapeMismatch(
        shape([1, 84, 300]),
        3,
      );
      expect(mismatch, contains('3 labels'));
    });

    test('one matching candidate accepts the shape', () {
      expect(
        DetectorModelService.labelShapeMismatch(shape([1, 84, 300]), 80),
        isNull,
      );
      expect(
        DetectorModelService.labelShapeMismatch(shape([1, 300, 84]), 80),
        isNull,
      );
    });

    test('an uninterpretable shape has no opinion', () {
      expect(DetectorModelService.labelShapeMismatch(shape([1, 3]), 3), isNull);
    });
  });
}
