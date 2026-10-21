import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../models/app_settings.dart';
import '../services/settings_service.dart';
import '../services/telemetry_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_home_theme.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

/// Settings — runtime configuration for users and facilitators.
///
/// The Settings subtree uses a locally scoped light visual theme
/// ([buildHomeTheme]) matching the Home/Help light surface; the global dark
/// theme and the shell navigation bar are unchanged. The light surface is
/// scoped to the Settings subtree only and must not leak into other tabs or
/// the shell navigation bar.
///
/// Values are persisted by [SettingsService]. The optional [telemetry] input
/// is read-only and drives the System Performance card's retained averages.
class SettingsScreen extends StatelessWidget {
  final SettingsService settings;
  final VoidCallback onOpenLogsReports;

  /// Optional read-only telemetry source for the System Performance card.
  ///
  /// When `null`, the card renders `—` placeholders with no live updates.
  final TelemetryService? telemetry;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onOpenLogsReports,
    this.telemetry,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildHomeTheme(),
      // The Settings subtree uses a light surface, so the status bar icons
      // must be dark to remain visible against it. The global dark theme keeps
      // light icons on the other (dark) screens; this AnnotatedRegion is
      // scoped to the Settings subtree only.
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          // The app-bar title uses the same `titleLarge` + ink treatment as the
          // Detection screen's `Detection Mode` header so the two top bars
          // share one typographic style. Background, elevation, and all other
          // app-bar behavior are unchanged.
          appBar: AppBar(
            title: Builder(
              builder: (context) => Text(
                'Settings',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: kHomeInk),
              ),
            ),
          ),
          body: ListenableBuilder(
            listenable: settings,
            builder: (context, _) {
              return SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final contentWidth = constraints.maxWidth;
                    // Bounded, centered width so the cards and text stay
                    // readable on wide constraints. Derived from available
                    // width, not the screenshot.
                    final boundedWidth = contentWidth > 480
                        ? 480.0
                        : contentWidth;
                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: boundedWidth),
                        child: ListView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: kSpace16,
                            vertical: kSpace16,
                          ),
                          children: [
                            _SettingsCard(
                              title: 'Preferences',
                              children: [
                                SwitchListTile(
                                  title: const Text('Vibration Feedback'),
                                  subtitle: const Text(
                                    'Vibrate on detections and gestures',
                                  ),
                                  value: settings.vibrationFeedback,
                                  onChanged: settings.setVibrationFeedback,
                                ),
                                SwitchListTile(
                                  title: const Text('Auto-Start on Open'),
                                  subtitle: const Text(
                                    'Begin detection automatically when EyeCue opens',
                                  ),
                                  value: settings.autoStartDetection,
                                  onChanged: settings.setAutoStartDetection,
                                ),
                                SwitchListTile(
                                  title: const Text('Low Power Mode'),
                                  subtitle: const Text(
                                    'Reduce inference rate to conserve battery',
                                  ),
                                  value: settings.lowPowerMode,
                                  onChanged: settings.setLowPowerMode,
                                ),
                                SwitchListTile(
                                  title: const Text('Hide Bottom Navigation'),
                                  subtitle: const Text(
                                    'Hides the bottom bar only. Destinations and '
                                    'swipe navigation still work. Android '
                                    'accessibility navigation keeps the bar '
                                    'visible.',
                                  ),
                                  value: settings.hideBottomNavigation,
                                  onChanged: settings.setHideBottomNavigation,
                                ),
                              ],
                            ),
                            _SettingsCard(
                              title: 'Audio Guidance',
                              children: [
                                // The child title is vertically aligned with the
                                // parent section title by removing the tile's
                                // default vertical content padding, so the
                                // leading text baseline lines up with the
                                // heading above it. The child title color/weight
                                // already match the parent and are unchanged.
                                SwitchListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: kSpace16,
                                  ),
                                  title: const Text('Audio / Voice Guidance'),
                                  subtitle: const Text(
                                    'Speak detected objects and guidance',
                                  ),
                                  value: settings.audioEnabled,
                                  onChanged: settings.setAudioEnabled,
                                ),
                              ],
                            ),
                            _SettingsCard(
                              title: 'Engine & Sensitivity',
                              children: [
                                RadioGroup<InferenceEngine>(
                                  groupValue: settings.inferenceEngine,
                                  onChanged: (value) {
                                    if (value != null) {
                                      settings.setInferenceEngine(value);
                                    }
                                  },
                                  child: Column(
                                    children: [
                                      // The label rows share the parent title's
                                      // leading edge (kSpace16) and use the same
                                      // w800 weight as the parent section title.
                                      const ListTile(
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: kSpace16,
                                        ),
                                        title: Text(
                                          'Recommended',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        subtitle: Text(
                                          'The native engine used for detection.',
                                        ),
                                      ),
                                      RadioListTile<InferenceEngine>(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: kSpace16,
                                            ),
                                        controlAffinity:
                                            ListTileControlAffinity.trailing,
                                        title: Text(
                                          InferenceEngine.ultralytics.label,
                                        ),
                                        subtitle: Text(
                                          InferenceEngine
                                              .ultralytics
                                              .description,
                                        ),
                                        value: InferenceEngine.ultralytics,
                                      ),
                                    ],
                                  ),
                                ),
                                _SensitivityControls(settings: settings),
                              ],
                            ),
                            _SettingsCard(
                              title: 'Distance & Overlays',
                              children: [
                                RadioGroup<DistanceEstimationMode>(
                                  groupValue: settings.distanceEstimationMode,
                                  onChanged: (value) {
                                    if (value != null) {
                                      settings.setDistanceEstimationMode(value);
                                    }
                                  },
                                  child: Column(
                                    children: [
                                      for (final option
                                          in DistanceEstimationMode.values)
                                        RadioListTile<DistanceEstimationMode>(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: kSpace16,
                                              ),
                                          controlAffinity:
                                              ListTileControlAffinity.trailing,
                                          title: Text(option.label),
                                          subtitle: Text(option.description),
                                          value: option,
                                        ),
                                    ],
                                  ),
                                ),
                                SwitchListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: kSpace16,
                                  ),
                                  title: const Text('Show Bounding Boxes'),
                                  subtitle: const Text(
                                    'Draw a box around each detected object',
                                  ),
                                  value: settings.showBoundingBoxes,
                                  onChanged: settings.setShowBoundingBoxes,
                                ),
                                SwitchListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: kSpace16,
                                  ),
                                  title: const Text('Show Depth Heatmap'),
                                  subtitle: const Text(
                                    'Colour the scene by estimated distance',
                                  ),
                                  // The preference is preserved while the
                                  // bounding-box mode is selected; only the
                                  // control is disabled.
                                  value: settings.showDepthHeatmap,
                                  onChanged:
                                      settings.distanceEstimationMode ==
                                          DistanceEstimationMode.monocularDepth
                                      ? settings.setShowDepthHeatmap
                                      : null,
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    kSpace16,
                                    kSpace4,
                                    kSpace16,
                                    0,
                                  ),
                                  child: Text(
                                    'Distances in metres are estimates from the '
                                    'depth model and are not calibrated '
                                    'measurements.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: kHomeInkMuted),
                                  ),
                                ),
                              ],
                            ),
                            _SystemPerformanceCard(
                              telemetry: telemetry,
                              onOpenLogsReports: onOpenLogsReports,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SensitivityControls extends StatefulWidget {
  final SettingsService settings;

  const _SensitivityControls({required this.settings});

  @override
  State<_SensitivityControls> createState() => _SensitivityControlsState();
}

class _SensitivityControlsState extends State<_SensitivityControls> {
  late double _draft = widget.settings.detectionConfidence;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_handleSettingsChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_handleSettingsChanged);
    super.dispose();
  }

  void _handleSettingsChanged() {
    final confidence = widget.settings.detectionConfidence;
    if (confidence == _draft || !mounted) return;
    setState(() => _draft = confidence);
  }

  @override
  Widget build(BuildContext context) {
    final preset = DetectionSensitivityPreset.fromThreshold(_draft);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RadioGroup<DetectionSensitivityPreset>(
          groupValue: preset,
          onChanged: (value) {
            if (value == null) return;
            setState(() => _draft = value.threshold);
            widget.settings.setDetectionConfidence(value.threshold);
          },
          child: Column(
            children: [
              // The sensitivity presets are sub-options of the engine option,
              // so their text is indented to the right of the parent row using
              // the existing spacing token. The indent is
              // applied through contentPadding (not a wrapping Padding) so the
              // trailing radio controls keep the same horizontal position as
              // the other radios and stay vertically aligned with each other.
              for (final option in DetectionSensitivityPreset.values)
                RadioListTile<DetectionSensitivityPreset>(
                  contentPadding: const EdgeInsets.only(
                    left: kSpace32,
                    right: kSpace16,
                  ),
                  controlAffinity: ListTileControlAffinity.trailing,
                  title: Text(option.label),
                  subtitle: Text(option.description),
                  value: option,
                ),
            ],
          ),
        ),
        Semantics(
          container: true,
          label:
              'Advanced detection confidence threshold, '
              '${_draft.toStringAsFixed(2)}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Advanced threshold: ${_draft.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Slider(
                min: AppSettings.minDetectionConfidence,
                max: AppSettings.maxDetectionConfidence,
                divisions:
                    ((AppSettings.maxDetectionConfidence -
                                AppSettings.minDetectionConfidence) /
                            0.05)
                        .round(),
                value: _draft,
                label: _draft.toStringAsFixed(2),
                onChanged: (value) {
                  setState(
                    () => _draft = AppSettings.normalizeDetectionConfidence(
                      value,
                    ),
                  );
                },
                onChangeEnd: (value) {
                  final normalized = AppSettings.normalizeDetectionConfidence(
                    value,
                  );
                  setState(() => _draft = normalized);
                  widget.settings.setDetectionConfidence(normalized);
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Lower values find more objects. Higher values reduce false alerts. Changes apply after detection restarts.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A light Settings card: a heading header and the card's controls, exposed as
/// one coherent semantic group with the heading as the group's semantic
/// heading. The decorative section icon was removed; the heading alone carries
/// the section meaning.
class _SettingsCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A Material ancestor is required so the card's ListTile/SwitchListTile/
    // RadioListTile children paint their ink splashes on the card surface
    // rather than being hidden by the card's background decoration.
    return Container(
      margin: const EdgeInsets.only(bottom: kSpace16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius24),
        boxShadow: kHomeShadowSoft,
      ),
      child: Material(
        color: kHomeSurfaceCard,
        borderRadius: BorderRadius.circular(kRadius24),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          // Vertical padding only: the horizontal inset is applied to the
          // heading below so the parent section title shares the same leading
          // edge as its child rows (whose ListTile contentPadding is
          // `kSpace16`). This aligns every parent title with its children.
          padding: const EdgeInsets.symmetric(vertical: kSpace16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: kSpace16),
                child: Semantics(
                  // The card heading is the semantic heading for the group. The
                  // inner Text is excluded so the heading is exposed exactly
                  // once (no duplicate label from the visual text).
                  container: true,
                  header: true,
                  label: title,
                  child: ExcludeSemantics(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: kSpace8),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// The single dark Settings card: retained telemetry averages plus the
/// researcher-facing Logs & Reports entry.
///
/// The three metrics are truthful retained/rolling averages from
/// [TelemetryService] (`Avg FPS`, `Avg latency`, `Avg confidence`). When the
/// retained lists are empty — or [telemetry] is `null` — every metric shows
/// `—` (em dash) rather than a misleading measured `0`. No accuracy,
/// precision, recall, F1, or mAP value is displayed.
class _SystemPerformanceCard extends StatelessWidget {
  final TelemetryService? telemetry;
  final VoidCallback onOpenLogsReports;

  const _SystemPerformanceCard({
    required this.telemetry,
    required this.onOpenLogsReports,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Light foreground derived from the active light ColorScheme (seeded from
    // kHomeAccentCyan), suitable for the dark kHomeInk surface.
    final foreground = theme.colorScheme.onPrimary;
    final mutedForeground = foreground.withValues(alpha: 0.7);
    // The System Performance title uses the light cyan accent; the retained
    // chevron uses the primary cyan accent.
    final titleAccent = kHomeAccentCyanLight;
    final chevronAccent = kHomeAccentCyan;

    final service = telemetry;
    final hasSamples = service != null && service.samples.isNotEmpty;
    final hasRecords = service != null && service.records.isNotEmpty;

    final fps = hasSamples
        ? service.averageInferenceFps.toStringAsFixed(1)
        : '—';
    final latency = hasSamples
        ? service.averageLatencyMs.toStringAsFixed(1)
        : '—';
    final confidence = hasRecords
        ? service.averageConfidence.toStringAsFixed(2)
        : '—';

    // A Material ancestor is required so the card's ListTile paints its ink
    // splash on the dark card surface rather than being hidden by the card's
    // background decoration.
    return Container(
      margin: const EdgeInsets.only(bottom: kSpace16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius24),
        boxShadow: kHomeShadowSoft,
      ),
      child: Material(
        color: kHomeInk,
        borderRadius: BorderRadius.circular(kRadius24),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          // Uniform card padding. The parent-title leading-edge alignment
          // applied to the other Settings cards was reverted for this card, so
          // the heading is not wrapped in an extra horizontal Padding.
          padding: const EdgeInsets.all(kSpace16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                container: true,
                header: true,
                label: 'System Performance',
                child: ExcludeSemantics(
                  child: Text(
                    'System Performance',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: titleAccent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: kSpace16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PerformanceMetric(
                      value: fps,
                      label: 'Avg FPS',
                      valueColor: foreground,
                      labelColor: mutedForeground,
                    ),
                  ),
                  Expanded(
                    child: _PerformanceMetric(
                      value: latency,
                      label: 'Avg latency (MS)',
                      valueColor: foreground,
                      labelColor: mutedForeground,
                    ),
                  ),
                  Expanded(
                    child: _PerformanceMetric(
                      value: confidence,
                      label: 'Avg confidence',
                      valueColor: foreground,
                      labelColor: mutedForeground,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: kSpace16),
              // The action area uses the tokenized overlay-white-11 inner
              // surface; the retained chevron uses the cyan accent. The
              // ListTile is wrapped in its own Material so its ink splash
              // paints on the overlay surface rather than being hidden by the
              // intermediate DecoratedBox.
              Material(
                color: kHomeOverlayWhite11,
                borderRadius: BorderRadius.circular(kRadius14),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: kSpace12,
                  ),
                  // The chevron is relocated to the trailing (right) side of
                  // the tile; the subtitle was removed so only the title
                  // remains. The title/chevron colors and the navigation
                  // callback are unchanged.
                  trailing: ExcludeSemantics(
                    child: Icon(Icons.chevron_right, color: chevronAccent),
                  ),
                  title: Text(
                    'View Logs & Reports',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: foreground,
                    ),
                  ),
                  onTap: onOpenLogsReports,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One metric column inside the dark System Performance card: a value and its
/// label, exposed as text/semantics (never color-only) and never a live region.
class _PerformanceMetric extends StatelessWidget {
  final String value;
  final String label;
  final Color valueColor;
  final Color labelColor;

  const _PerformanceMetric({
    required this.value,
    required this.label,
    required this.valueColor,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
        const SizedBox(height: kSpace6),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(color: labelColor),
        ),
      ],
    );
  }
}
