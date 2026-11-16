# Documentation audit — 16 November 2026

## Coverage

Reviewed **all 98 existing tracked Markdown documents and both license texts**, including root docs, nested frontend plans, design-token notes, the original specification transcript, and the vendored plugin's English/Chinese/iOS guides, nine topic guides and changelog. Added this audit and the [documentation index](index.md), bringing the documented inventory to **102 files**. Runtime label data and build source such as `CMakeLists.txt` are not prose documentation.

The source baseline was fast-forwarded from `879be04` to `aadf9e0` (remote main, PR #17) without discarding the pre-existing `.gitignore` or session-log edits. Three lighter subagents reviewed disjoint technical, release/privacy, and historical/frontend groups; the coordinating review reconciled root status/planning docs, links, coverage, and cross-document contradictions.

Current code/workflows take precedence over earlier prose. Source checks included public and Study entry points, manifests and Gradle, Settings/export schemas, native accessibility fixes, model labels/assets and hashes, telemetry serialization/validators, UI semantics, tests and CI definitions. The unchanged licenses and original conversation remain historical/source material rather than new operational instructions.

## Main corrections

- Public/Study identities, entry points, permissions and research-route boundaries.
- Campus detector and 14 labels, optional depth, single native engine, settings schema 8, export schema 4.
- Flutter-versus-Dart SDK requirements, matching flavor/entry-point commands, signing, cloud artifacts, and optional internal-track upload.
- Retired Custom-engine tasks, superseded schedules/percentages and revision-specific test/device results.
- Source links after retired files and moved documentation, line-citation URL syntax, and old architecture anchors.
- Current Settings slider/hover crash-fix source, with no new device-verification claim.
- Purpose-based local/remote branch names and matching workflow triggers. Published history/attribution correction is separately prepared and requires its own final application; this audit is not proof that a remote history rewrite has occurred.

## Verification and limits

Local Markdown file/image targets and Markdown heading anchors were checked across the complete inventory. Actionable local targets resolve; old citations into removed source are retained as explicit historical code references. The two generic plugin `example/` links now explain that the example directory is omitted from this fork. Line citations use valid source anchors, and Markdown-document links point to the document rather than unsupported `:line` paths.

The frozen `chat_spec.md` conversation contains **27 unresolved numeric transcript citation placeholders**. They were reviewed and retained as original conversation artifacts, not silently counted as valid operational links. External URL reachability, hosted policy contents, native timing, service deployment and Play status were not checked by this audit. Source line anchors are navigation hints, not proof that a historical line number still describes current source.

`git diff --check` and control-character checks passed. No Flutter dependency installation, analyzer/test run, APK/AAB build, physical-device check, backend upload or research measurement was performed for this docs pass. Dated results in the existing records retain their stated scope.

## File-by-file results

95 updated, 5 reviewed and retained, 2 added.

| Document | Review result | Finding / treatment |
| --- | --- | --- |
| [LICENSE](../LICENSE) | reviewed-retained | Compared with the vendored plugin license; identical SHA-256, retained without wording changes. |
| [README.md](../README.md) | updated | Rewrote current setup, variants, model/runtime summary, documentation map and source/license pointers. |
| [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) | updated | Recorded current campus detector metadata, exact label list and AGPL string without asserting dataset/distribution rights; described depth as runtime-optional; softened unsupported legal/source-compliance conclusions. |
| [auditor.md](../auditor.md) | updated | Added current reconciliation while preserving the original early-prototype audit findings. |
| [chat_spec.md](../chat_spec.md) | reviewed-retained | Reviewed as the original frozen conversation/specification; obsolete code and citation placeholders retained as historical evidence. |
| [design-reference/tokens/extracted-design-tokens-screenshot.md](../design-reference/tokens/extracted-design-tokens-screenshot.md) | updated | Marked contradictory screenshot decisions historical and crosslinked the shipped redesign/current navigation. |
| [docs/alert-responsiveness.md](alert-responsiveness.md) | updated | Scoped shared alert behavior versus Study-only trial snapshots/records to the two entrypoints. |
| [docs/app-only-implementation-plan.md](app-only-implementation-plan.md) | updated | Added specific reconciliation for the original 15-task plan; retained historical acceptance criteria. |
| [docs/architecture.md](architecture.md) | updated | Replaced removed Dart/TFLite engine map with current Android native detector, optional depth path, public/Study wiring, telemetry, and source map at aadf9e0. |
| [docs/benchmark-procedure.md](benchmark-procedure.md) | updated | Rebased procedure on current single detector and Study debug entrypoint; fixed package IDs/export picker path and distinguished historical results from current-model evidence. |
| [docs/benchmark-results.md](benchmark-results.md) | updated | Marked all YOLOv8 measurements as historical and stated no current campus-detector benchmark is recorded. |
| [docs/camera-path-forensics.md](camera-path-forensics.md) | updated | Kept 2026-08 measurements intact; clarified retired camera path and active YOLOView path. |
| [docs/changelog.md](changelog.md) | updated | Added maintenance record without claiming a new app release or fresh runtime results. |
| [docs/cloud-builds.md](cloud-builds.md) | updated | Aligned branch trigger reference, CI steps/toolchain wording, internal upload behavior, and app privacy-link destination with the workflow and current public/Study flavors. |
| [docs/component-inventory.md](component-inventory.md) | updated | Corrected root docs source-of-truth note and marked Logs & Reports as Study-only; kept screenshot cells blank absent verified Figma exports. |
| [docs/comprehensive-project-assessment-2026-08-21.md](comprehensive-project-assessment-2026-08-21.md) | updated | Preserved the assessed revision and added current engine, entry-point, and Campus-label facts with status crosslink. |
| [docs/development-workflow.md](development-workflow.md) | updated | Corrected SDK/flavor commands, verification scope and consolidated-workspace recovery. |
| [docs/documentation-audit.md](documentation-audit.md) | added | Added file-by-file review coverage, evidence scope and verification exceptions. |
| [docs/dual-inference-engine-test.md](dual-inference-engine-test.md) | updated | Marked engine comparison retired after Custom removal; retained historical runs/protocol. |
| [docs/frontend-onboarding-analysis.md](frontend-onboarding-analysis.md) | updated | Corrected current screen/entry-point map and flagged obsolete duplicate mirror process; repaired links. |
| [docs/frontend-workflow/charts-logs-polish-analysis.md](frontend-workflow/charts-logs-polish-analysis.md) | updated | Recorded shipped viewport, chart-axis, and Logs layout specifics with code links; retained the phase findings as historical scope. |
| [docs/frontend-workflow/charts-logs-polish-design-spec.md](frontend-workflow/charts-logs-polish-design-spec.md) | updated | Linked the completed geometry and chart decisions to live widgets and the device verification record. |
| [docs/frontend-workflow/charts-logs-polish-plan.md](frontend-workflow/charts-logs-polish-plan.md) | updated | Marked the implementation complete and replaced obsolete scope-as-instructions framing with current source pointers. |
| [docs/frontend-workflow/custom-detector-priority-distance-alert-policy-analysis.md](frontend-workflow/custom-detector-priority-distance-alert-policy-analysis.md) | updated | Linked implemented detector-aware alert ranking to AlertPolicy and the active model identity; recorded 14-label Campus built-in. |
| [docs/frontend-workflow/custom-detector-priority-distance-alert-policy-plan.md](frontend-workflow/custom-detector-priority-distance-alert-policy-plan.md) | updated | Marked the policy implemented and distinguished imported-model logic from the removed Custom inference engine. |
| [docs/frontend-workflow/detection-alignment-charts-analysis.md](frontend-workflow/detection-alignment-charts-analysis.md) | updated | Linked shipped Detection gutter, heatmap, chart, and Logs behavior to live sources and the verification record. |
| [docs/frontend-workflow/detection-alignment-charts-design-spec.md](frontend-workflow/detection-alignment-charts-design-spec.md) | updated | Recorded which decisions shipped and where each is now implemented. |
| [docs/frontend-workflow/detection-alignment-charts-plan.md](frontend-workflow/detection-alignment-charts-plan.md) | updated | Closed the dated implementation plan against live source and device verification. |
| [docs/frontend-workflow/detection-redesign-plan.md](frontend-workflow/detection-redesign-plan.md) | updated | Marked shared lifecycle/redesign shipped; documented single active Ultralytics screen and retired Custom-screen steps. |
| [docs/frontend-workflow/detection-screen-analysis.md](frontend-workflow/detection-screen-analysis.md) | updated | Identified the current EngineDetectionScreen/Ultralytics screen and preserved the earlier two-engine analysis as history. |
| [docs/frontend-workflow/detection-screen-design-spec.md](frontend-workflow/detection-screen-design-spec.md) | updated | Updated authority pointers to current Detection screen and shipped refinement documents. |
| [docs/frontend-workflow/detection-screen-plan.md](frontend-workflow/detection-screen-plan.md) | updated | Clarified the planned Custom screen is retired and linked current Detection implementation. |
| [docs/frontend-workflow/fresh-detection-speech-revalidation-analysis.md](frontend-workflow/fresh-detection-speech-revalidation-analysis.md) | updated | Linked implemented result revalidation and shared tracker/speech path; noted fix commit. |
| [docs/frontend-workflow/fresh-detection-speech-revalidation-plan.md](frontend-workflow/fresh-detection-speech-revalidation-plan.md) | updated | Marked the accepted implementation present and the plan historical. |
| [docs/frontend-workflow/help-screen-analysis.md](frontend-workflow/help-screen-analysis.md) | updated | Linked the current Help screen, public Privacy Policy action, launch-failure regression test, and redesign history. |
| [docs/frontend-workflow/help-screen-design-spec.md](frontend-workflow/help-screen-design-spec.md) | updated | Recorded current Help behavior and the public Privacy Policy launch-failure test without rewriting the earlier spec. |
| [docs/frontend-workflow/help-screen-plan.md](frontend-workflow/help-screen-plan.md) | updated | Marked redesign history and linked the shipped Privacy Policy action plus launch-failure coverage. |
| [docs/frontend-workflow/home-detection-state-plan.md](frontend-workflow/home-detection-state-plan.md) | updated | Marked shell-owned EngineCoordinator and sole active Ultralytics screen; removed links to retired Custom lifecycle types. |
| [docs/frontend-workflow/home-screen-analysis.md](frontend-workflow/home-screen-analysis.md) | updated | Linked implemented Home screen/design closeout and repaired stale/misrooted citations. |
| [docs/frontend-workflow/home-screen-design-spec.md](frontend-workflow/home-screen-design-spec.md) | updated | Linked current Home source and implemented redesign records. |
| [docs/frontend-workflow/home-screen-plan.md](frontend-workflow/home-screen-plan.md) | updated | Marked redesign shipped and restored missing token-source link. |
| [docs/frontend-workflow/logs-reports-screen-analysis.md](frontend-workflow/logs-reports-screen-analysis.md) | updated | Documented public-versus-Study Logs wiring and linked later shipped chart/subtitle polish. |
| [docs/frontend-workflow/logs-reports-screen-design-spec.md](frontend-workflow/logs-reports-screen-design-spec.md) | updated | Corrected the public/Study surface distinction and linked current Logs implementation/refinements. |
| [docs/frontend-workflow/logs-reports-screen-plan.md](frontend-workflow/logs-reports-screen-plan.md) | updated | Marked implementation shipped and distinguished public Logs from Study research-session surfaces. |
| [docs/frontend-workflow/navigation-plan.md](frontend-workflow/navigation-plan.md) | updated | Recorded AppShell ownership and implemented four-tab/relative-swipe behavior; plan is no longer pending. |
| [docs/frontend-workflow/settings-screen-analysis.md](frontend-workflow/settings-screen-analysis.md) | updated | Recorded model-based Settings selection and the merged Slider-label accessibility fix at review base aadf9e0. |
| [docs/frontend-workflow/settings-screen-design-spec.md](frontend-workflow/settings-screen-design-spec.md) | updated | Recorded current model-selection UI and Slider semantics follow-up with updated regression coverage. |
| [docs/frontend-workflow/settings-screen-plan.md](frontend-workflow/settings-screen-plan.md) | updated | Marked redesign shipped and noted Slider-label change plus retained semantic formatter callbacks. |
| [docs/frontend-workflow/talkback-ownership-analysis.md](frontend-workflow/talkback-ownership-analysis.md) | updated | Reconciled semantic-control status with merged Slider-label assertions and Android hover guard at main@aadf9e0; no new build/device result claimed. |
| [docs/frontend-workflow/talkback-ownership-plan.md](frontend-workflow/talkback-ownership-plan.md) | updated | Reconciled completed plan with post-plan Slider and MainActivity accessibility fixes; no new verification claimed. |
| [docs/frontend-workflow/talkback-semantics-analysis.md](frontend-workflow/talkback-semantics-analysis.md) | updated | Updated status for merged Slider semantics and Android hover crash guard while preserving the historical decision record. |
| [docs/frontend-workflow/talkback-semantics-plan.md](frontend-workflow/talkback-semantics-plan.md) | updated | Updated implementation status for Slider label removal, retained formatter callbacks, test coverage, and Android hover guard. |
| [docs/frontend-workflow/visual-redesign.md](frontend-workflow/visual-redesign.md) | updated | Retained confirmed closeout while linking later Detection refinements and public/Study entry points. |
| [docs/icon-generation.md](icon-generation.md) | updated | Removed stale link to the deleted in-app PNG encoder and described current host-side generation boundary. |
| [docs/implementation-decisions.md](implementation-decisions.md) | updated | Marked Decisions 1–10 and YOLOv8 NCHW candidate as superseded historical records; updated current model, alert telemetry schema, and test-evidence wording. |
| [docs/implementation-plan.md](implementation-plan.md) | updated | Replaced obsolete isolate/dual-engine milestones and unsupported schedules with current development stages. |
| [docs/implementation-progress.md](implementation-progress.md) | updated | Added current implementation summary, retained dated phase results, retired stale current-work estimates. |
| [docs/index.md](index.md) | added | Added a complete navigation map distinguishing current guides, dated records, frontend history and plugin documentation. |
| [docs/inference-pipeline-probe.md](inference-pipeline-probe.md) | updated | Preserved probe output and static-image evidence; marked procedures non-runnable on current plugin path. |
| [docs/inference-tensor-diagnosis.md](inference-tensor-diagnosis.md) | updated | Preserved tensor diagnosis and marked ByteBuffer recommendation as pertaining to the retired isolate. |
| [docs/ingest-threat-model.md](ingest-threat-model.md) | updated | Corrected asset description to distinguish server-side collection integrity from device-retained local trials, which are not a guaranteed backup. |
| [docs/input-pipeline-investigation.md](input-pipeline-investigation.md) | updated | Preserved probe measurements and clarified the input probe/isolate no longer exist. |
| [docs/known-issues.md](known-issues.md) | updated | Replaced retired Custom-engine blockers with current native/model/depth/data/release evidence gaps. |
| [docs/log-export.md](log-export.md) | updated | Clarified Study entrypoint wiring and made version-code-2 artifact statement historical; retained SAF export behavior and local-data limits. |
| [docs/mde-integration.md](mde-integration.md) | updated | Reframed branch-specific test/device results as dated historical evidence and documented current Study-only research-session wiring and current validation limits. |
| [docs/model-assets.md](model-assets.md) | updated | Replaced stale YOLOv8 artifact as current model with the bundled campus detector (14 ordered labels, size/hash/provenance) and current optional depth asset; retained import contract with current boundaries. |
| [docs/orientation-design-review.md](orientation-design-review.md) | updated | Preserved proposal while clarifying active orientation belongs to the Ultralytics plugin path. |
| [docs/orientation-implementation.md](orientation-implementation.md) | updated | Preserved implementation evidence while identifying removed files and current plugin-owned orientation. |
| [docs/painter-coordinate-review.md](painter-coordinate-review.md) | updated | Preserved coordinate math and limited its conclusions to the former CameraPreview path. |
| [docs/phase1-preprocessing-diagnosis.md](phase1-preprocessing-diagnosis.md) | updated | Preserved measurements while clarifying the instrumented Custom path is removed. |
| [docs/play-internal-automation.md](play-internal-automation.md) | reviewed-retained | Matches workflow dispatch gating, signed public AAB upload to the internal track, artifact ordering, credential handling, and action pin; no content correction needed. |
| [docs/play-store-checklist.md](play-store-checklist.md) | updated | Corrected privacy-link gap and endpoint-encryption gate; now distinguishes implemented HTTPS URL validation from unverified deployed TLS/service state. |
| [docs/play-store-listing.md](play-store-listing.md) | updated | Updated draft to identify the fixed campus detector and its 14 classes, describe depth as optional, replace the privacy placeholder with the configured destination plus live-verification caveat, and avoid claiming source publication. |
| [docs/play-store-readiness.md](play-store-readiness.md) | updated | Reframed as a historical ledger and added 2026-11-16 source-only status for SDK constraint, flavors, assets, privacy-link destination, and unresolved external state. |
| [docs/privacy-and-data-safety.md](privacy-and-data-safety.md) | updated | Documented public Help URL and Study hiding behavior; distinguished code behavior from hosted/deployed state; corrected token treatment/classification and Data Safety caveats. |
| [docs/project-status.md](project-status.md) | updated | Reconciled current source, remote fast-forward, evidence limits and next priorities. |
| [docs/release-procedure.md](release-procedure.md) | updated | Corrected current flavor/build guidance, Study telemetry and signing requirements, optional depth/bundled campus-model summary, privacy URL verification, and legal/source-offer caveats; preserved dated measurements as historical evidence. |
| [docs/release-readiness-report.md](release-readiness-report.md) | updated | Marked the 2026-10-25/26 verification and classifications as historical, added current-source audit reference, corrected privacy URL status and stale telemetry threat description, and preserved dated outcomes. |
| [docs/research-notes.md](research-notes.md) | updated | Replaced stale current-model claim with campus detector/depth model and reframed YOLOv8 paper/candidate content as historical planning/evidence. |
| [docs/session-log.md](session-log.md) | updated | Added session scope and verification limits while preserving prior entries and the pre-existing edit. |
| [docs/static-image-test.md](static-image-test.md) | updated | Kept historical bus-photo results intact; marked deleted fixture/mode and current detector path. |
| [docs/study-installation.md](study-installation.md) | updated | Corrected local helper provenance filename (BUILD.json), separated it from cloud BUILD.txt, and replaced the incorrect respondent-specific version-code instruction with release increment guidance. |
| [docs/supabase-research-telemetry.md](supabase-research-telemetry.md) | updated | Documented manual Study-flavor upload wiring and public entrypoint exclusion; reviewed token, edge function, and schema contract against local code/migrations. |
| [docs/telemetry-data-dictionary.md](telemetry-data-dictionary.md) | updated | Updated schema status and detector identity/label semantics for the campus model; clarified device-validation boundary. |
| [docs/testing-plan.md](testing-plan.md) | updated | Reframed suite counts/device checks as dated evidence; separated removed isolate/dual-engine plans from current native single-engine architecture and Study-only reporting. |
| [docs/thesis-product-status-audit.md](thesis-product-status-audit.md) | updated | Distinguished the dated thesis assessment and percentages from current implementation evidence. |
| [docs/ui-conventions.md](ui-conventions.md) | updated | Preserved dated TalkBack/device evidence and clarified it is not current-main validation; retained current project verification policy. |
| [plugins/ultralytics_yolo/CHANGELOG.md](../plugins/ultralytics_yolo/CHANGELOG.md) | reviewed-retained | Reviewed as preserved upstream release history; latest entry is 0.6.13 and it includes upstream 0.6.10 depth support. Left unchanged. |
| [plugins/ultralytics_yolo/LICENSE](../plugins/ultralytics_yolo/LICENSE) | reviewed-retained | Upstream AGPL-3.0 text; SHA-256 matches root LICENSE and file was left untouched. |
| [plugins/ultralytics_yolo/README.md](../plugins/ultralytics_yolo/README.md) | updated | Retained generic plugin instructions and added EyeCue-specific Android/model/flavor scope links. |
| [plugins/ultralytics_yolo/README.zh-CN.md](../plugins/ultralytics_yolo/README.zh-CN.md) | updated | Retained generic plugin instructions, corrected package example version to 0.6.13, and added EyeCue-specific scope links. |
| [plugins/ultralytics_yolo/VENDORED.md](../plugins/ultralytics_yolo/VENDORED.md) | updated | Corrected the parity-check expectation so it accounts for intentional source deviations and notes that diff output count varies. |
| [plugins/ultralytics_yolo/doc/api.md](../plugins/ultralytics_yolo/doc/api.md) | updated | Reviewed generic API descriptions against plugin surface; added EyeCue scope note so API capabilities are not mistaken for app configuration. |
| [plugins/ultralytics_yolo/doc/index.md](../plugins/ultralytics_yolo/doc/index.md) | updated | Reviewed generic plugin overview and added app-versus-plugin scope note. |
| [plugins/ultralytics_yolo/doc/install.md](../plugins/ultralytics_yolo/doc/install.md) | updated | Corrected dependency example to vendored plugin version 0.6.13; added generic plugin versus EyeCue platform scope note. |
| [plugins/ultralytics_yolo/doc/models.md](../plugins/ultralytics_yolo/doc/models.md) | updated | Reviewed generic official/custom model flows and added EyeCue asset/offline behavior scope note. |
| [plugins/ultralytics_yolo/doc/performance.md](../plugins/ultralytics_yolo/doc/performance.md) | updated | Retained plugin device benchmark evidence as plugin-specific; added note that it is not EyeCue campus-model performance. |
| [plugins/ultralytics_yolo/doc/quickstart.md](../plugins/ultralytics_yolo/doc/quickstart.md) | updated | Reviewed generic plugin quickstart against current API and added EyeCue-specific scope note. |
| [plugins/ultralytics_yolo/doc/troubleshooting.md](../plugins/ultralytics_yolo/doc/troubleshooting.md) | updated | Reviewed generic plugin diagnostics and added EyeCue-specific usage scope note. |
| [plugins/ultralytics_yolo/doc/usage.md](../plugins/ultralytics_yolo/doc/usage.md) | updated | Reviewed generic usage patterns and added note that plugin capabilities do not describe EyeCue app support. |
| [plugins/ultralytics_yolo/doc/use_gpu_feature.md](../plugins/ultralytics_yolo/doc/use_gpu_feature.md) | updated | Reviewed generic accelerator behavior and added EyeCue scope note; generic device performance data remains plugin-specific. |
| [plugins/ultralytics_yolo/ios/ultralytics_yolo/Sources/ultralytics_yolo/README.md](../plugins/ultralytics_yolo/ios/ultralytics_yolo/Sources/ultralytics_yolo/README.md) | updated | Retained generic plugin iOS-layer documentation and clarified that the root EyeCue app has Android runtime only. |
