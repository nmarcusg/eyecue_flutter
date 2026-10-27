import 'dart:typed_data';

import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/models/detector_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tfliteFingerprint', () {
    test('is content-derived, stable, and hex-16 plus byte length', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final first = tfliteFingerprint(bytes);
      expect(first, tfliteFingerprint(Uint8List.fromList([1, 2, 3, 4])));
      expect(first, matches(RegExp(r'^[0-9a-f]{16}-4$')));
    });

    test('distinguishes different graph contents', () {
      final a = tfliteFingerprint(Uint8List.fromList([1, 2, 3, 4]));
      final b = tfliteFingerprint(Uint8List.fromList([1, 2, 3, 5]));
      final longer = tfliteFingerprint(Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(a, isNot(b));
      expect(a, isNot(longer));
    });
  });

  group('DetectorModel', () {
    test('built-in carries the readable name and a fixed fingerprint', () {
      final model = DetectorModel.builtIn(const ['person', 'bicycle']);
      expect(model.kind, DetectorModelKind.builtIn);
      expect(model.displayName, 'Built-in YOLOv8n');
      expect(model.fingerprint, 'builtin-yolov8n-int8-metadata');
      expect(model.path, 'assets/yolov8n_int8_new_metadata.tflite');
      expect(model.ref.id, 'builtin');
      expect(model.ref.classCount, 2);
    });

    test('custom ref id uses the first 12 hex chars of the fingerprint', () {
      const model = DetectorModel(
        kind: DetectorModelKind.custom,
        displayName: 'Obstacle Detector v2',
        fingerprint: '0123456789abcdef-1234',
        labels: ['obstacle'],
        fileSizeBytes: 1234,
        path: '/tmp/0123456789abcdef-1234.tflite',
      );
      expect(model.ref.id, 'custom:0123456789ab');
      expect(model.ref.name, 'Obstacle Detector v2');
      expect(model.ref.fingerprint, '0123456789abcdef-1234');
      expect(model.ref.classCount, 1);
    });
  });

  group('priorityForClass', () {
    test('built-in keeps the COCO class-id policy', () {
      expect(
        priorityForClass(DetectorModelKind.builtIn, 0, 'anything'),
        ObjectPriority.high,
      );
      expect(
        priorityForClass(DetectorModelKind.builtIn, 56, 'anything'),
        ObjectPriority.medium,
      );
      expect(
        priorityForClass(DetectorModelKind.builtIn, 77, 'anything'),
        ObjectPriority.low,
      );
    });

    test('custom class 0 is high only because its label is a person', () {
      expect(
        priorityForClass(DetectorModelKind.custom, 0, 'person'),
        ObjectPriority.high,
      );
    });

    test('custom class 0 with an unrelated label stays low', () {
      expect(
        priorityForClass(DetectorModelKind.custom, 0, 'mug'),
        ObjectPriority.low,
      );
    });

    test('custom labels ignore the COCO meaning of their class id', () {
      // COCO 2 is `car` (high); this custom model's class 2 is a chair.
      expect(
        priorityForClass(DetectorModelKind.custom, 2, 'chair'),
        ObjectPriority.medium,
      );
      // COCO 56 is `chair` (medium); this custom model's class 56 is a person.
      expect(
        priorityForClass(DetectorModelKind.custom, 56, 'person'),
        ObjectPriority.high,
      );
    });

    test('custom labels fold underscores and casing', () {
      expect(
        priorityForClass(DetectorModelKind.custom, 7, 'traffic_light'),
        ObjectPriority.high,
      );
      expect(
        priorityForClass(DetectorModelKind.custom, 9, 'Stop Sign'),
        ObjectPriority.high,
      );
    });
  });

  group('normalizeLabelName', () {
    test('lowercases, folds separators, and collapses whitespace', () {
      expect(normalizeLabelName(' Traffic_Light '), 'traffic light');
      expect(normalizeLabelName('dining-table'), 'dining table');
      expect(normalizeLabelName('Walking   Person'), 'walking person');
    });
  });

  group('AppSettings detector fields', () {
    test('legacy JSON without detector fields selects the built-in model', () {
      final settings = AppSettings.fromJson({
        'schemaVersion': 6,
        'vibrationFeedback': false,
      });
      expect(settings.detectorModelKind, DetectorModelKind.builtIn);
      expect(settings.customModelName, isNull);
      expect(settings.customModelPath, isNull);
      expect(AppSettings.currentSchemaVersion, 7);
    });

    test('a custom selection round-trips and clears as a unit', () {
      final settings = AppSettings.fromJson({
        'detectorModelKind': 'custom',
        'customModelName': 'Obstacle Detector v2',
        'customModelFingerprint': '0123456789abcdef-1234',
        'customModelPath': '/data/user/0/app/eyecue_models/x.tflite',
        'customModelClassCount': 3,
      });
      expect(settings.detectorModelKind, DetectorModelKind.custom);
      expect(settings.customModelClassCount, 3);

      final builtIn = settings.copyWith(
        detectorModelKind: DetectorModelKind.builtIn,
        customModelName: null,
        customModelFingerprint: null,
        customModelPath: null,
        customModelClassCount: null,
      );
      expect(builtIn.detectorModelKind, DetectorModelKind.builtIn);
      expect(builtIn.customModelName, isNull);
      expect(builtIn.customModelPath, isNull);
    });

    test('a custom kind without its identity falls back to built-in', () {
      final settings = AppSettings.fromJson({
        'detectorModelKind': 'custom',
        'customModelName': 'Half written',
      });
      expect(settings.detectorModelKind, DetectorModelKind.builtIn);
      expect(settings.customModelName, isNull);
    });
  });
}
