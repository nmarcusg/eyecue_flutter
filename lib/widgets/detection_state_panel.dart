import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/detection_runtime_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_home_theme.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import 'accessible_button.dart';

/// Shared, actionable status surface for camera and model lifecycle events.
///
/// The panel deliberately renders the safe failure message instead of the
/// underlying exception. Technical details remain available to telemetry and
/// logs through [DetectionFailure.technicalDetail].
class DetectionStatePanel extends StatelessWidget {
  final DetectionRuntimeState state;
  final DetectionFailure? failure;
  final VoidCallback? onRetry;
  final VoidCallback? onFallback;
  final VoidCallback? onStop;

  const DetectionStatePanel({
    super.key,
    required this.state,
    this.failure,
    this.onRetry,
    this.onFallback,
    this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveFailure = failure;
    final message = effectiveFailure?.userMessage ?? _defaultMessage(state);
    final title = effectiveFailure == null
        ? state.label
        : effectiveFailure.category.label;
    final canOpenSettings =
        effectiveFailure?.category == DetectionFailureCategory.permissionDenied;

    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $message',
      child: Card(
        color: kHomeSurfaceCard,
        elevation: 0,
        margin: const EdgeInsets.all(kSpace24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadius24),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kRadius24),
            boxShadow: kHomeShadowSoft,
          ),
          child: Padding(
            padding: const EdgeInsets.all(kSpace20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(child: Icon(_iconFor(state), size: 64)),
                  const SizedBox(height: kSpace12),
                  ExcludeSemantics(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: kHomeInk,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: kSpace8),
                  ExcludeSemantics(
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kHomeInkMuted),
                    ),
                  ),
                  const SizedBox(height: kSpace20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: kSpace8,
                    runSpacing: kSpace8,
                    children: [
                      if (canOpenSettings)
                        AccessibleButton(
                          label: 'Open Settings',
                          icon: Icons.settings,
                          prominent: true,
                          onPressed: openAppSettings,
                        ),
                      if (onRetry != null)
                        AccessibleButton(
                          label: 'Retry',
                          icon: Icons.refresh,
                          prominent: !canOpenSettings,
                          onPressed: onRetry,
                        ),
                      if (onFallback != null)
                        AccessibleButton(
                          label: 'Use fallback',
                          icon: Icons.alt_route,
                          onPressed: onFallback,
                        ),
                      if (onStop != null)
                        AccessibleButton(
                          label: 'Stop',
                          icon: Icons.stop_circle,
                          onPressed: onStop,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(DetectionRuntimeState state) => switch (state) {
    DetectionRuntimeState.requestingPermission => Icons.camera_alt_outlined,
    DetectionRuntimeState.startingCamera => Icons.videocam_outlined,
    DetectionRuntimeState.loadingModel => Icons.memory_outlined,
    DetectionRuntimeState.recovering => Icons.restart_alt,
    DetectionRuntimeState.fallback => Icons.alt_route,
    DetectionRuntimeState.failed => Icons.error_outline,
    DetectionRuntimeState.paused => Icons.pause_circle_outline,
    DetectionRuntimeState.ready => Icons.check_circle_outline,
    DetectionRuntimeState.disposed => Icons.stop_circle_outlined,
    DetectionRuntimeState.idle => Icons.center_focus_strong_outlined,
  };

  static String _defaultMessage(DetectionRuntimeState state) => switch (state) {
    DetectionRuntimeState.idle => 'Detection is ready to start.',
    DetectionRuntimeState.requestingPermission =>
      'Camera permission is needed to detect objects.',
    DetectionRuntimeState.startingCamera => 'Starting the camera.',
    DetectionRuntimeState.loadingModel => 'Loading the detection model.',
    DetectionRuntimeState.ready => 'Detection is ready.',
    DetectionRuntimeState.paused => 'Detection is paused.',
    DetectionRuntimeState.recovering => 'Recovering detection. Please wait.',
    DetectionRuntimeState.fallback =>
      'The recommended engine is unavailable. A compatibility engine is active.',
    DetectionRuntimeState.failed => 'Detection is unavailable.',
    DetectionRuntimeState.disposed => 'Detection has stopped.',
  };
}
