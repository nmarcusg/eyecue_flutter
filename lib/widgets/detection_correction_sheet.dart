import 'package:flutter/material.dart';

import '../models/detection_correction.dart';
import '../models/detection_info.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'accessible_button.dart';

/// Accessible first-level correction flow for one normalized detection.
class DetectionCorrectionSheet extends StatefulWidget {
  final DetectionInfo info;
  final Iterable<String> labels;

  const DetectionCorrectionSheet({
    super.key,
    required this.info,
    required this.labels,
  });

  @override
  State<DetectionCorrectionSheet> createState() =>
      _DetectionCorrectionSheetState();
}

class _DetectionCorrectionSheetState extends State<DetectionCorrectionSheet> {
  String _query = '';
  CorrectionFeedback? _feedback;
  String? _correctedLabel;

  List<String> get _filteredLabels {
    final query = _query.trim().toLowerCase();
    final labels = widget.labels.toList(growable: false);
    if (query.isEmpty) return labels;
    return labels
        .where((label) => label.toLowerCase().contains(query))
        .toList(growable: false);
  }

  void _select(CorrectionFeedback feedback) {
    if (feedback != CorrectionFeedback.incorrect) {
      _complete(feedback);
      return;
    }
    setState(() => _feedback = feedback);
  }

  void _complete(CorrectionFeedback feedback) {
    Navigator.of(context).pop(
      DetectionCorrectionSelection(
        feedback: feedback,
        correctedLabel: _correctedLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showingLabels = _feedback == CorrectionFeedback.incorrect;
    return SafeArea(
      child: Material(
        color: kHomeSurfaceCard,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            kSpace20,
            kSpace12,
            kSpace20,
            kSpace20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                showingLabels
                    ? 'Choose the intended label'
                    : 'Report detection',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: kHomeInk,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: kSpace8),
              Semantics(
                container: true,
                label: widget.info.semanticLabel,
                child: ExcludeSemantics(
                  child: Text(
                    'Detected ${widget.info.label}.',
                    style: TextStyle(color: kHomeInkMuted),
                  ),
                ),
              ),
              const SizedBox(height: kSpace16),
              if (!showingLabels) ...[
                AccessibleButton(
                  label: 'Correct',
                  icon: Icons.check_circle_outline,
                  onPressed: () => _select(CorrectionFeedback.correct),
                ),
                AccessibleButton(
                  label: 'Incorrect',
                  icon: Icons.cancel_outlined,
                  onPressed: () => _select(CorrectionFeedback.incorrect),
                ),
                AccessibleButton(
                  label: 'Unsure',
                  icon: Icons.help_outline,
                  onPressed: () => _select(CorrectionFeedback.unsure),
                ),
              ] else ...[
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Search labels',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: RadioGroup<String>(
                    groupValue: _correctedLabel,
                    onChanged: (value) =>
                        setState(() => _correctedLabel = value),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filteredLabels.length,
                      itemBuilder: (context, index) {
                        final label = _filteredLabels[index];
                        return RadioListTile<String>(
                          title: Text(label),
                          value: label,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                AccessibleButton(
                  label: _correctedLabel == null
                      ? 'Save incorrect report'
                      : 'Save incorrect report as $_correctedLabel',
                  icon: Icons.save_outlined,
                  onPressed: () => _complete(CorrectionFeedback.incorrect),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _feedback = null;
                    _correctedLabel = null;
                  }),
                  child: const Text('Back'),
                ),
              ],
              if (!showingLabels)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the correction flow and returns the completed selection, or `null`
/// when the user dismisses it without saving.
Future<DetectionCorrectionSelection?> showDetectionCorrectionSheet({
  required BuildContext context,
  required DetectionInfo info,
  required Iterable<String> labels,
}) {
  return showModalBottomSheet<DetectionCorrectionSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DetectionCorrectionSheet(info: info, labels: labels),
    ),
  );
}

/// Result returned by [DetectionCorrectionSheet] when a user completes a
/// correction. A dismissed sheet returns null and creates no record.
class DetectionCorrectionSelection {
  final CorrectionFeedback feedback;
  final String? correctedLabel;

  const DetectionCorrectionSelection({
    required this.feedback,
    this.correctedLabel,
  });

  String get confirmationMessage {
    return switch (feedback) {
      CorrectionFeedback.correct =>
        'Correction saved. Detection marked correct.',
      CorrectionFeedback.incorrect when correctedLabel != null =>
        'Correction saved. Detection marked incorrect as $correctedLabel.',
      CorrectionFeedback.incorrect =>
        'Correction saved. Detection marked incorrect.',
      CorrectionFeedback.unsure => 'Correction saved. Detection marked unsure.',
    };
  }
}
