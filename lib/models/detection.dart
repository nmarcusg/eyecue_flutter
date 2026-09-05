import 'dart:ui';

class Detection {
  final int classId;
  final String label;
  final double confidence;
  final Rect box; // x, y, w, h normalized (0.0 to 1.0)

  const Detection({
    required this.classId,
    required this.label,
    required this.confidence,
    required this.box,
  });

  Map<String, dynamic> toJson() => {
    'classId': classId,
    'label': label,
    'confidence': confidence,
    'box': {
      'left': box.left,
      'top': box.top,
      'width': box.width,
      'height': box.height,
    },
  };

  factory Detection.fromJson(Map<String, dynamic> json) {
    final box = json['box'] as Map<dynamic, dynamic>?;
    return Detection(
      classId: (json['classId'] as num?)?.toInt() ?? -1,
      label: json['label'] as String? ?? 'unknown',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      box: Rect.fromLTWH(
        (box?['left'] as num?)?.toDouble() ?? 0,
        (box?['top'] as num?)?.toDouble() ?? 0,
        (box?['width'] as num?)?.toDouble() ?? 0,
        (box?['height'] as num?)?.toDouble() ?? 0,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Detection &&
      other.classId == classId &&
      other.label == label &&
      other.confidence == confidence &&
      other.box == box;

  @override
  int get hashCode => Object.hash(classId, label, confidence, box);
}
