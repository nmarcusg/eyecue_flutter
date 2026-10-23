import '../models/app_settings.dart';

/// Pure derivation of the effective inference cadence from the stored targets
/// and the runtime gates (low power mode, distance estimation mode).
///
/// No Flutter imports, no timers and no I/O: callers own the actual scheduling
/// and only read the resolved values. Stored requests are never rewritten here;
/// clamps are reported through [lowPowerClamped] and [sourceLimited] so the UI
/// and telemetry can explain them.
class InferenceCadence {
  const InferenceCadence({
    required this.requestedDetectionHz,
    required this.requestedDepthHz,
    required this.effectiveDetectionHz,
    required this.effectiveDepthHz,
    required this.depthEnabled,
    required this.lowPowerClamped,
    required this.sourceLimited,
  });

  /// Low power mode never runs the detector faster than this.
  static const int lowPowerDetectionCapHz = 4;

  /// Low power mode never runs depth inference faster than this.
  static const int lowPowerDepthCapHz = 2;

  /// Stored detector target; `null` means Automatic.
  final int? requestedDetectionHz;

  /// Stored depth target.
  final int requestedDepthHz;

  /// Cadence the detector may actually run at; `null` means uncapped.
  final int? effectiveDetectionHz;

  /// Cadence depth inference may actually run at; `0` when depth work is off.
  final int effectiveDepthHz;

  /// Whether depth inference runs at all in the current mode.
  final bool depthEnabled;

  /// Low power mode lowered a requested target below the stored value.
  final bool lowPowerClamped;

  /// The depth target exceeds the numeric detector cadence that feeds it.
  final bool sourceLimited;

  /// Scheduling interval for depth inference; `null` when depth work is off.
  Duration? get depthInterval => depthEnabled && effectiveDepthHz > 0
      ? Duration(milliseconds: (1000 / effectiveDepthHz).round())
      : null;

  static InferenceCadence resolve({
    required int? requestedDetectionHz,
    required int requestedDepthHz,
    required bool lowPowerMode,
    required DistanceEstimationMode distanceEstimationMode,
  }) {
    final effectiveDetectionHz = lowPowerMode
        ? _min(
            requestedDetectionHz ?? lowPowerDetectionCapHz,
            lowPowerDetectionCapHz,
          )
        : requestedDetectionHz;
    final depthEnabled =
        distanceEstimationMode == DistanceEstimationMode.monocularDepth;
    final effectiveDepthHz = !depthEnabled
        ? 0
        : _min(
            _min(
              requestedDepthHz,
              lowPowerMode ? lowPowerDepthCapHz : requestedDepthHz,
            ),
            effectiveDetectionHz ?? requestedDepthHz,
          );
    final detectionClamped =
        lowPowerMode &&
        (requestedDetectionHz == null ||
            requestedDetectionHz > lowPowerDetectionCapHz);
    // A mode-disabled depth target is not a clamp: the stored value is kept.
    final depthClamped =
        depthEnabled && lowPowerMode && requestedDepthHz > lowPowerDepthCapHz;

    return InferenceCadence(
      requestedDetectionHz: requestedDetectionHz,
      requestedDepthHz: requestedDepthHz,
      effectiveDetectionHz: effectiveDetectionHz,
      effectiveDepthHz: effectiveDepthHz,
      depthEnabled: depthEnabled,
      lowPowerClamped: detectionClamped || depthClamped,
      sourceLimited:
          depthEnabled &&
          effectiveDetectionHz != null &&
          requestedDepthHz > effectiveDetectionHz,
    );
  }

  static int _min(int a, int b) => a < b ? a : b;
}
