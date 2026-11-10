import 'package:eyecue_flutter/models/detector_model.dart';
import 'package:eyecue_flutter/services/telemetry_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('historical YOLOv8n and campus records stay distinguishable', () {
    final campus = DetectorModel.builtIn(const ['bench', 'person']).ref;
    final models = DetectorModelTable();
    final oldKey = models.keyFor(
      'builtin',
      'Built-in YOLOv8n',
      'builtin-yolov8n-int8-metadata',
    );
    final newKey = models.keyFor(campus.id, campus.name, campus.fingerprint);
    expect(oldKey, isNot(newKey));
    expect(models.models[oldKey]!['name'], 'Built-in YOLOv8n');
    expect(models.models[newKey]!['name'], 'EyeCue campus detector');
  });
}
