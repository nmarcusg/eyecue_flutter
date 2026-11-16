# EyeCue documentation index

Reviewed **2026-11-16** against local `main` at `aadf9e0`. Source and workflow definitions establish implemented behavior; dated logs establish only the checks they record. This review does not add runtime measurements, test totals, or live Play/backend verification.

Start with the [root README](../README.md) and [project status](project-status.md). See the [file-by-file documentation audit](documentation-audit.md) for coverage, validation results and retained historical material.

## Current guides and contracts

- [Project status](project-status.md)
- [Architecture](architecture.md)
- [Component inventory](component-inventory.md)
- [Model assets](model-assets.md)
- [Mde integration](mde-integration.md)
- [Alert responsiveness](alert-responsiveness.md)
- [Ui conventions](ui-conventions.md)
- [Development workflow](development-workflow.md)
- [Implementation plan](implementation-plan.md)
- [Known issues](known-issues.md)
- [Testing plan](testing-plan.md)
- [Benchmark procedure](benchmark-procedure.md)
- [Log export](log-export.md)
- [Telemetry data dictionary](telemetry-data-dictionary.md)
- [Supabase research telemetry](supabase-research-telemetry.md)
- [Ingest threat model](ingest-threat-model.md)
- [Cloud builds](cloud-builds.md)
- [Study installation](study-installation.md)
- [Release procedure](release-procedure.md)
- [Play internal automation](play-internal-automation.md)
- [Privacy and data safety](privacy-and-data-safety.md)
- [Play store listing](play-store-listing.md)
- [Play store checklist](play-store-checklist.md)
- [Icon generation](icon-generation.md)

## Evidence and implementation records

These combine dated entries with current context. Test totals, model results and release-readiness conclusions apply to their stated revision, not automatically to the current checkout.

- [Implementation progress](implementation-progress.md)
- [Implementation decisions](implementation-decisions.md)
- [Session log](session-log.md)
- [Changelog](changelog.md)
- [Benchmark results](benchmark-results.md)
- [Research notes](research-notes.md)
- [Play store readiness](play-store-readiness.md)
- [Release readiness report](release-readiness-report.md)

## Historical records

The following preserve earlier designs, audits or retired pipeline investigations. Read their current-status/reconciliation notes first; removed source references do not imply that the old code still exists.

- [App only implementation plan](app-only-implementation-plan.md)
- [Thesis product status audit](thesis-product-status-audit.md)
- [Frontend onboarding analysis](frontend-onboarding-analysis.md)
- [Comprehensive project assessment 2026 08 21](comprehensive-project-assessment-2026-08-21.md)
- [Camera path forensics](camera-path-forensics.md)
- [Dual inference engine test](dual-inference-engine-test.md)
- [Inference pipeline probe](inference-pipeline-probe.md)
- [Inference tensor diagnosis](inference-tensor-diagnosis.md)
- [Input pipeline investigation](input-pipeline-investigation.md)
- [Orientation design review](orientation-design-review.md)
- [Orientation implementation](orientation-implementation.md)
- [Painter coordinate review](painter-coordinate-review.md)
- [Phase1 preprocessing diagnosis](phase1-preprocessing-diagnosis.md)
- [Static image test](static-image-test.md)

- [Original project audit](../auditor.md): July 2026 findings, with a current reconciliation.
- [Original conversation/specification transcript](../chat_spec.md): preserved historical conversation, including obsolete examples and unresolved transcript citation placeholders. It is not an executable setup guide.
- [Extracted design tokens](../design-reference/tokens/extracted-design-tokens-screenshot.md): original visual reference with current implementation context.

## Frontend design and implementation history

- [Charts logs polish analysis](frontend-workflow/charts-logs-polish-analysis.md)
- [Charts logs polish design spec](frontend-workflow/charts-logs-polish-design-spec.md)
- [Charts logs polish plan](frontend-workflow/charts-logs-polish-plan.md)
- [Custom detector priority distance alert policy analysis](frontend-workflow/custom-detector-priority-distance-alert-policy-analysis.md)
- [Custom detector priority distance alert policy plan](frontend-workflow/custom-detector-priority-distance-alert-policy-plan.md)
- [Detection alignment charts analysis](frontend-workflow/detection-alignment-charts-analysis.md)
- [Detection alignment charts design spec](frontend-workflow/detection-alignment-charts-design-spec.md)
- [Detection alignment charts plan](frontend-workflow/detection-alignment-charts-plan.md)
- [Detection redesign plan](frontend-workflow/detection-redesign-plan.md)
- [Detection screen analysis](frontend-workflow/detection-screen-analysis.md)
- [Detection screen design spec](frontend-workflow/detection-screen-design-spec.md)
- [Detection screen plan](frontend-workflow/detection-screen-plan.md)
- [Fresh detection speech revalidation analysis](frontend-workflow/fresh-detection-speech-revalidation-analysis.md)
- [Fresh detection speech revalidation plan](frontend-workflow/fresh-detection-speech-revalidation-plan.md)
- [Help screen analysis](frontend-workflow/help-screen-analysis.md)
- [Help screen design spec](frontend-workflow/help-screen-design-spec.md)
- [Help screen plan](frontend-workflow/help-screen-plan.md)
- [Home detection state plan](frontend-workflow/home-detection-state-plan.md)
- [Home screen analysis](frontend-workflow/home-screen-analysis.md)
- [Home screen design spec](frontend-workflow/home-screen-design-spec.md)
- [Home screen plan](frontend-workflow/home-screen-plan.md)
- [Logs reports screen analysis](frontend-workflow/logs-reports-screen-analysis.md)
- [Logs reports screen design spec](frontend-workflow/logs-reports-screen-design-spec.md)
- [Logs reports screen plan](frontend-workflow/logs-reports-screen-plan.md)
- [Navigation plan](frontend-workflow/navigation-plan.md)
- [Settings screen analysis](frontend-workflow/settings-screen-analysis.md)
- [Settings screen design spec](frontend-workflow/settings-screen-design-spec.md)
- [Settings screen plan](frontend-workflow/settings-screen-plan.md)
- [Talkback ownership analysis](frontend-workflow/talkback-ownership-analysis.md)
- [Talkback ownership plan](frontend-workflow/talkback-ownership-plan.md)
- [Talkback semantics analysis](frontend-workflow/talkback-semantics-analysis.md)
- [Talkback semantics plan](frontend-workflow/talkback-semantics-plan.md)
- [Visual redesign](frontend-workflow/visual-redesign.md)

## Vendored plugin and licensing

EyeCue consumes a modified local plugin. Generic upstream examples and platform support are not promises that EyeCue supports every example/platform. Begin with [fork maintenance and deviations](../plugins/ultralytics_yolo/VENDORED.md), then consult the package's [documentation index](../plugins/ultralytics_yolo/doc/index.md), [English README](../plugins/ultralytics_yolo/README.md), [Chinese README](../plugins/ultralytics_yolo/README.zh-CN.md), and [upstream changelog](../plugins/ultralytics_yolo/CHANGELOG.md).

Preserve the application [license](../LICENSE), plugin [license](../plugins/ultralytics_yolo/LICENSE), and [third-party notices](../THIRD_PARTY_NOTICES.md). The audit does not establish external legal clearance.
