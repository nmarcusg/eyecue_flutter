import 'dart:ui';

import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../models/detection.dart';

abstract final class UltralyticsDetectionAdapter {
  static List<Detection> convert(
    List<YOLOResult> results,
    List<String> labels,
  ) {
    return results
        .map((result) {
          final box = result.normalizedBox;
          final left = box.left.clamp(0.0, 1.0);
          final top = box.top.clamp(0.0, 1.0);
          final right = box.right.clamp(left, 1.0);
          final bottom = box.bottom.clamp(top, 1.0);
          final classId = result.classIndex;
          final label = classId >= 0 && classId < labels.length
              ? labels[classId]
              : result.className;
          return Detection(
            classId: classId,
            label: label,
            confidence: result.confidence,
            box: Rect.fromLTRB(left, top, right, bottom),
          );
        })
        .toList(growable: false);
  }
}
