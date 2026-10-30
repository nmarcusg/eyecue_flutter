# Third-party notices

Inventory of the third-party components that are vendored into, compiled into or
shipped inside an EyeCue release artefact, with the obligations they carry and the
items that require qualified legal review.

**This document gives no legal opinion.** It records what is in the tree, what the
upstream licences say, and which questions only a lawyer (or the copyright holder)
can answer. Nothing here replaces the upstream licence texts, which are
authoritative.

Every fact below is inspectable in this tree; the evidence for the release build is
in [`docs/release-procedure.md`](docs/release-procedure.md) §6 and
[`docs/release-readiness-report.md`](docs/release-readiness-report.md).

## 1. The application's own licence — `AGPL-3.0-only`

The EyeCue application source is licensed **`AGPL-3.0-only`** (SPDX), © the EyeCue
project owner. The complete licence text is in [`LICENSE`](LICENSE): the canonical GNU
Affero General Public License version 3, copied byte-for-byte from the vendored
plugin's upstream copy at [`plugins/ultralytics_yolo/LICENSE`](plugins/ultralytics_yolo/LICENSE)
(both sha256 `4df3c306dddaaf4baffdff5ca820cc679ac8cd6dc263c6a74517783e42fa7a3b`).

Owner decision **D2** in [`docs/play-store-readiness.md`](docs/play-store-readiness.md)
§8 is therefore **decided**: the application carries the same licence as the
YOLO/Ultralytics components in §2 and §3.

The consequence is that the AGPL-3.0 obligations now apply to the application's own
code as well as to the vendored plugin and the bundled models. Every binary distributed
from this tree must be accompanied by the complete corresponding source of the whole
work, and source distribution is a duty for the app itself, not only for the plugin
(§7). What those duties mean in practice — notice wording, "corresponding source" for
weights, network use (§13), and app-store distribution terms — is listed as review
items **R1–R7** in §6: **obligations identified, legal review not performed**.

## 2. Vendored plugin — `ultralytics_yolo` 0.6.13 (AGPL-3.0)

| Field | Value |
| --- | --- |
| Path | [`plugins/ultralytics_yolo`](plugins/ultralytics_yolo) |
| Upstream | `ultralytics_yolo` 0.6.13 (`https://pub.dev/packages/ultralytics_yolo/versions/0.6.13`) |
| Consumed as | `path: plugins/ultralytics_yolo` in [`pubspec.yaml`](pubspec.yaml) |
| Licence | **AGPL-3.0** |
| Licence text | [`plugins/ultralytics_yolo/LICENSE`](plugins/ultralytics_yolo/LICENSE) — upstream copy, **preserved verbatim, must not be edited** |
| Fork record | [`plugins/ultralytics_yolo/VENDORED.md`](plugins/ultralytics_yolo/VENDORED.md) — provenance, parity check, upgrade obligations |
| Fork approval | owner decision **D4** (already approved) |

The plugin's Dart and Kotlin sources are compiled into the app, so AGPL-3.0 §5
(source of the work as distributed) applies to those files.

### 2.1 Local modifications (must be published with the source)

The vendored copy is not pristine upstream: eight numbered deviations exist, one per
modified Kotlin file, all added for the native shared-frame depth transport. They are
documented in full — with why each is needed and how to re-apply it on an upstream
upgrade — in [`VENDORED.md`](plugins/ultralytics_yolo/VENDORED.md) §"Native deviation
list". Summary:

| # | File | Deviation |
| --- | --- | --- |
| 1 | `YOLOStreamConfig.kt` | `depthInstanceId`, `depthIntervalMs`, `depthMaxDim` fields + `custom(...)` parameters |
| 2 | `YOLOView.kt` | latest analysis bitmap, single-thread depth executor under a lock, in-flight guard, failure latch, depth tick + event emission, teardown in `stop()`/`pauseCamera()` |
| 3 | `YOLOPlatformView.kt` | parse the three depth keys on the initial-config and `setStreamingConfig` paths |
| 4 | `YOLOInstanceManager.kt` | `shared` companion instance, `includeRawData`/`drawOverlays` pass-through on `predict(...)`, `predictorInstance(...)` returns `Predictor?` |
| 5 | `YOLOPlugin.kt` | the plugin field points at `YOLOInstanceManager.shared` |
| 6 | `YOLOResult.kt` | `DepthMap` gains `grid`, `gridWidth`, `gridHeight` |
| 7 | `DepthEstimator.kt` | `gridMaxDim`, block-mean grid, and skipping colourisation/bitmap/dense `values` on the native-stream path |
| 8 | `YOLO.kt` | `predict(...)` gains `rotateForCamera`, `includeRawData`, `drawOverlays` |

The deviations are not Kotlin-only: four **Dart** files in the vendored copy also
diverge from upstream and carry the same publication obligation —
`plugins/ultralytics_yolo/lib/models/yolo_result.dart`,
`plugins/ultralytics_yolo/lib/widgets/yolo_controller.dart`,
`plugins/ultralytics_yolo/lib/yolo_streaming_config.dart` and
`plugins/ultralytics_yolo/lib/yolo_view.dart`. They are recorded in
[`VENDORED.md`](plugins/ultralytics_yolo/VENDORED.md) §"Dart surface". The eight
Kotlin rows above plus that section cover **every** file in the vendored copy that
differs from upstream, which is the set the notice duty below applies to.

AGPL-3.0 requires modified versions to carry prominent notices stating that they
were changed and the date. The deviations are recorded in `VENDORED.md` and in this
file; whether that satisfies "prominent notices" for each source file is review item
**R3** in §6.

## 3. Bundled model assets (AGPL-3.0, Ultralytics)

Both runtime models are compiled into the release bundle
(`base/assets/flutter_assets/assets/…`; see
[`docs/release-procedure.md`](docs/release-procedure.md) §6.1).

| Asset | Size | SHA-256 | Provenance |
| --- | --- | --- | --- |
| `assets/yolo26n-depth_w8a32.tflite` | 5 474 749 B | `8c7f242c2a8c339c6721863e103e17e026cbd784c9a3d031a8e902660c364311` | official `yolo26n-depth_w8a32.tflite` from the pinned `yolo-flutter-app` release `v0.6.6`, copied unchanged; its own `metadata.json` declares `"license": "AGPL-3.0 License (https://ultralytics.com/license)"` |
| `assets/yolov8n_int8_new_metadata.tflite` | 3 483 114 B | `3a571033aedd222957e6f8973f30e48b9c55bce1572306c3d8b523b2a7919b6a` | generated in-tree by [`tool/package_ultralytics_metadata.dart`](tool/package_ultralytics_metadata.dart) from an **externally supplied** YOLOv8n INT8 base graph (base SHA-256 `63bf9a81fe2e19f01b9ffe32531374c8a1f00d8e11ce5a0ce27008ce611d54fb`); packaging only appends a deterministic `metadata.json` and rewrites no weights |

Details and validation guarantees: [`docs/model-assets.md`](docs/model-assets.md).

Obligations that follow from shipping these weights:

* AGPL-3.0 §5 — the complete corresponding source of the work must accompany a
  distributed binary, or be offered per §6 (§7 below defines the procedure).
* AGPL-3.0 §6 — a written offer is only valid if it names a place and a period.
* For model weights, "corresponding source" is a contested concept (the weights are
  not source code; the training pipeline is not in this repository). Whether the
  bundled weights trigger §5/§6 at all, and what "source" means for them, is review
  item **R1** in §6 — **no opinion is offered here**.
* The detection model's metadata payload carries no licence string (only the depth
  model's does), and its base graph is not in the tree. That provenance gap is
  review item **R2**.

## 4. Dart / Flutter dependencies (`pubspec.lock`)

99 packages are pinned in [`pubspec.lock`](pubspec.lock) — the lockfile is
authoritative for exact versions. Direct dependencies:

| Package | Version | Kind |
| --- | --- | --- |
| `flutter` (SDK) | — | direct |
| `camera` | 0.12.1 | direct |
| `flutter_tts` | 4.2.5 | direct |
| `permission_handler` | 12.0.3 | direct |
| `path_provider` | 2.1.6 | direct |
| `fl_chart` | 1.2.0 | direct |
| `ultralytics_yolo` | 0.6.13 | direct (**vendored**, §2) |
| `marionette_flutter` | 0.6.0 | direct |
| `google_fonts` | 8.2.1 | direct |
| `flutter_lints` | 6.0.0 | dev |
| `flutter_test` (SDK) | — | dev |

Everything else is transitive (88 packages), including `camera_android_camerax`
0.7.4+7, `permission_handler_android` 13.0.1, `jni` 1.0.3, `shared_preferences*`,
`url_launcher*`, `wakelock_plus` 1.8.0, `xml`, `yaml`, `win32`.

No licence text is reproduced here. Each package's own `LICENSE` in its resolved
source is authoritative; the resolved sources are the pub-cache directories pinned
by the lockfile. A release must not be published with a dependency whose terms have
not been read — see review item **R4**.

## 5. Native / AAR dependencies visible in the release bundle

Android libraries that end up in the artefact, taken from the manifest-merger blame
report (`build/app/outputs/logs/manifest-merger-release-report.txt`) and the bundle
listing ([`docs/release-procedure.md`](docs/release-procedure.md) §6.1):

| Dependency | Version | Why it is present |
| --- | --- | --- |
| `androidx.camera:camera-core` / `camera-camera2` / `camera-camera2-pipe` / `camera-lifecycle` / `camera-video` / `camera-view` / `camera-featurecombinationquery` | 1.6.1 | `camera_android_camerax` (the camera pipeline) |
| `androidx.camera.viewfinder:viewfinder-core` | 1.5.1 | camerax |
| `com.google.ai.edge.litert:litert` | 2.1.5 | `ultralytics_yolo` native inference (via the plugin's LiteRT/CompiledModel path) |
| `androidx.work:work-runtime` | 2.11.2 | WorkManager, constructed on the startup path |
| `androidx.core:core` / `core-ktx` | 1.18.0 | framework support; also the source of the auto-generated `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` |
| `androidx.appcompat:appcompat` (+`-resources`) | 1.7.1 | theme/activity support |
| `androidx.exifinterface:exifinterface` | 1.4.2 | camerax metadata |
| `androidx.datastore:datastore*` | 1.1.7 | preferences storage used by a plugin |
| `androidx.browser:browser`, `androidx.activity:activity`, `androidx.fragment`, `androidx.room`, `androidx.lifecycle`, … | see blame report | transitive support libraries |

Shared objects shipped per ABI (three ABIs: `arm64-v8a`, `armeabi-v7a`, `x86_64`):
`libLiteRt.so`, `libLiteRtClGlAccelerator.so` (64-bit ABIs only), `libultralytics.so`,
`libimage_processing_util_jni.so`, `libsurface_util_jni.so`, `libdartjni.so`,
`libdatastore_shared_counter.so`, `libc++_shared.so`, `libapp.so`, `libflutter.so`.

Obligations: every AAR/SDK above ships its own licence (typically Apache-2.0 for
AndroidX, and the LiteRT/Ultralytics native stack carries its own terms), and their
notice/attribution requirements apply to redistributed binaries. Reading them and
deciding whether this file is a sufficient notice is review item **R5**.

## 6. Items requiring qualified legal review (no opinion given)

Obligations identified, **legal review not performed**: no item below has been
reviewed by counsel, and nothing in this file states that AGPL compliance is verified.

| # | Question | Why it matters |
| --- | --- | --- |
| R1 | Do the bundled Ultralytics **weights** trigger AGPL-3.0 §5/§6, and if so what counts as their "corresponding source"? | the models are redistributed inside the app bundle; the training pipeline is not here |
| R2 | Is the detection model's provenance (externally supplied base graph, no licence string in its metadata) sufficient? | the depth model names its licence; the detector's does not |
| R3 | Do the eight plugin deviations satisfy AGPL-3.0's "prominent notices … that you changed the files" requirement? | the plugin is a modified AGPL-3.0 work |
| R4 | Are all 99 pub dependencies under terms compatible with distribution and with the app's eventual licence? | no licence audit has been performed here |
| R5 | Do the native/AAR licences (AndroidX, LiteRT, Ultralytics native) require notices this repository does not currently produce? | redistributed binaries carry notice obligations |
| R6 | AGPL-3.0 §13 (network use): does the optional research-telemetry upload, or the separate research dashboard, make the covered work "interacted with … remotely through a computer network"? | the dashboard is a separate repository and is not deployed |
| R7 | Given §2–§5, what does the chosen `AGPL-3.0-only` (D2, decided) require in practice — notice wording, what counts as "source" for the weights, and how Play's distribution terms interact with it? | the licence choice is made; the practical duties are unanalysed by counsel |

## 7. AGPL-3.0 source-distribution procedure

Every release artefact must be accompanied by the corresponding source of the
AGPL-3.0 work — the application's own code, the modified vendored plugin and both
model assets. This repository **is** that source: everything is committed, together
with the build instructions for the modified plugin in
[`VENDORED.md`](plugins/ultralytics_yolo/VENDORED.md) and
[`docs/release-procedure.md`](docs/release-procedure.md) §4, so no separate download is
needed to satisfy the "complete corresponding source" requirement.

### 7.1 Tag ↔ `versionCode` matching (mandatory)

1. `versionCode` / `versionName` come from [`pubspec.yaml`](pubspec.yaml:5) and are
   passed to Gradle unchanged ([`docs/release-procedure.md`](docs/release-procedure.md) §2).
2. Before building a release, create an annotated tag on the exact commit that is
   built: `git tag -a v<versionName>+<versionCode> -m "EyeCue <versionName>+<versionCode> source"`
   (e.g. `v1.0.1+2`).
3. Record the tag and the built artefact SHA-256 together in the release notes, so a
   user holding the binary can name the exact source revision (§6 offer).
4. The tag must point at a commit whose `pubspec.yaml` carries the same
   `versionName`+`versionCode` as the artefact. Verify with
   `git show v<version>+<code>:pubspec.yaml | head -5`.
5. `-testsigned` fallback builds (`versionName …-testsigned`) are **not releases** and
   must not be tagged as one.

### 7.2 What is already in the repository

| AGPL-covered item | Path | Checked in? |
| --- | --- | --- |
| plugin Dart/Kotlin/CMake sources + upstream `LICENSE` | `plugins/ultralytics_yolo/**` | yes |
| plugin fork record (deviations, upgrade obligations) | `plugins/ultralytics_yolo/VENDORED.md` | yes |
| depth model asset | `assets/yolo26n-depth_w8a32.tflite` | yes |
| detection model asset | `assets/yolov8n_int8_new_metadata.tflite` | yes |
| labels | `assets/labels.txt` | yes |
| model provenance / packaging tool | `docs/model-assets.md`, `tool/package_ultralytics_metadata.dart` | yes |
| this notices file | `THIRD_PARTY_NOTICES.md` | yes |

### 7.3 Publishing the corresponding source for a release

```sh
# 1. from the tag, produce a source archive that provably matches the artefact
cd /home/nico/repos/eyecue_flutter-playstore
TAG=v<versionName>+<versionCode>
git archive --format=tar.gz --prefix="eyecue-${TAG}/" -o "eyecue-${TAG}-source.tar.gz" "${TAG}"
sha256sum "eyecue-${TAG}-source.tar.gz"   # publish alongside the AAB sha256

# 2. publish it where the §6 written offer points (owner: study site, repo mirror,
#    or a public repository tag) and keep it available for as long as the binaries are
```

Requirements that come from the licence, not from this procedure: the offer must name
a place and a period (§6), the source must be the *complete* corresponding source of
the AGPL-covered parts as actually distributed (§5), and the published copy must
include the notices in this file. Check items R1–R7 in §6 before any publication.

## 8. Status summary

| Item | State |
| --- | --- |
| Application licence (own code) | **`AGPL-3.0-only`** (D2 decided); canonical text in [`LICENSE`](LICENSE), byte-identical to the vendored plugin's copy |
| Vendored plugin licence text | present and unmodified |
| Fork deviations recorded | yes (8 numbered, in `VENDORED.md` and §2.1) |
| Model provenance recorded | yes (`docs/model-assets.md`); detector base graph not in tree (R2) |
| Pub dependency inventory | pinned in `pubspec.lock`; licence audit **not performed** (R4) |
| Native/AAR inventory | read out of the merger report; notice obligations **not audited** (R5) |
| AGPL source-distribution procedure | defined in §7 |
| Legal review | **not performed** — R1–R7 are open |
