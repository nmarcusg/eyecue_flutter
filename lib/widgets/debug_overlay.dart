import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/model_metadata.dart';

/// ---------------------------------------------------------------------------
/// DebugOverlay
///
/// A semi-transparent heads-up display rendered on top of the camera preview
/// in **debug builds only**. Shows real-time performance metrics, detection
/// information, and the **runtime model metadata** (exactly what the loaded
/// interpreter reports — never hardcoded) to help developers diagnose the
/// detection pipeline without reading logcat output.
///
/// The overlay is positioned in the top-left corner and uses a dark
/// semi-transparent background for readability against any camera scene.
/// ---------------------------------------------------------------------------
class DebugOverlay extends StatelessWidget {
  final double cameraFps;
  final double inferenceLatencyMs;
  final int detectionCount;
  final String? lastDetectionLabel;
  final double? lastConfidence;
  final int frameNumber;
  final int droppedFrames;
  final Size? cameraResolution;
  final String? imageFormat;
  final CameraLensDirection lensDirection;
  final ModelMetadata? modelMetadata;

  const DebugOverlay({
    super.key,
    required this.cameraFps,
    required this.inferenceLatencyMs,
    required this.detectionCount,
    required this.lastDetectionLabel,
    required this.lastConfidence,
    required this.frameNumber,
    required this.droppedFrames,
    required this.cameraResolution,
    required this.imageFormat,
    required this.lensDirection,
    this.modelMetadata,
  });

  @override
  Widget build(BuildContext context) {
    // Compute inference FPS from latency
    final inferenceFps = inferenceLatencyMs > 0
        ? (1000.0 / inferenceLatencyMs).toStringAsFixed(1)
        : '--';

    final resolutionStr = cameraResolution != null
        ? '${cameraResolution!.width.toInt()}×${cameraResolution!.height.toInt()}'
        : '?';

    final lensLabel = lensDirection == CameraLensDirection.front
        ? 'Front'
        : 'Back';

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 8,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xCC000000), // ~80% opaque black
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x44FFFFFF), width: 1),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFF00E676),
              height: 1.4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title row
                const Text(
                  '🐞 DEBUG OVERLAY',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFD600),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),

                // Runtime model metadata (self-describing)
                _sectionHeader('MODEL'),
                if (modelMetadata == null) ...[
                  _row('Model', '…'),
                  _row('Type', 'loading…'),
                ] else ...[
                  _row('Model', modelMetadata!.modelName),
                  _row('Type', modelMetadata!.modelType.label),
                  _row('Input', modelMetadata!.inputType.name.toUpperCase()),
                  _row('Output', modelMetadata!.outputType.name.toUpperCase()),
                  _row('Input Shape', _shapeLabel(modelMetadata!.inputShape)),
                  _row('Output Shape', _shapeLabel(modelMetadata!.outputShape)),
                  _row('Classes', modelMetadata!.classes.toString()),
                  _row('Anchors', modelMetadata!.anchors.toString()),
                  _row(
                    'Quantized',
                    modelMetadata!.inputQuantized ||
                            modelMetadata!.outputQuantized
                        ? 'Yes'
                        : 'No',
                    valueColor:
                        modelMetadata!.inputQuantized ||
                            modelMetadata!.outputQuantized
                        ? const Color(0xFFFFD600)
                        : const Color(0xFFEEEEEE),
                  ),
                  if (modelMetadata!.inputQuantized) ...[
                    _row('In Scale', _num(modelMetadata!.inputScale)),
                    _row('In ZeroPt', modelMetadata!.inputZeroPoint.toString()),
                  ],
                  if (modelMetadata!.outputQuantized) ...[
                    _row('Out Scale', _num(modelMetadata!.outputScale)),
                    _row(
                      'Out ZeroPt',
                      modelMetadata!.outputZeroPoint.toString(),
                    ),
                  ],
                ],
                const SizedBox(height: 4),

                // Performance metrics
                _sectionHeader('PERFORMANCE'),
                _row('Camera FPS', cameraFps.toStringAsFixed(1)),
                _row('Infer FPS', inferenceFps),
                _row('Latency', '${inferenceLatencyMs.toStringAsFixed(1)} ms'),
                _row('Frame #', frameNumber.toString()),
                _row('Dropped', droppedFrames.toString()),
                const SizedBox(height: 2),

                // Detection info
                _row(
                  'Detections',
                  detectionCount.toString(),
                  valueColor: detectionCount > 0
                      ? const Color(0xFF00E676)
                      : const Color(0xFFFF5252),
                ),
                if (lastDetectionLabel != null) ...[
                  _row('Last Obj', lastDetectionLabel!),
                  _row(
                    'Confidence',
                    lastConfidence != null
                        ? '${(lastConfidence! * 100).toStringAsFixed(1)}%'
                        : '--',
                  ),
                ],
                const SizedBox(height: 2),

                // Camera info
                _sectionHeader('CAMERA'),
                _row('Res', resolutionStr),
                _row('Lens', lensLabel),
                _row('Format', imageFormat ?? '?'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1, top: 2),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFFFFD600),
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xAAAAAAAA)),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: valueColor ?? const Color(0xFFEEEEEE),
            ),
          ),
        ],
      ),
    );
  }

  static String _shapeLabel(List<int> shape) => shape.join('×');

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
