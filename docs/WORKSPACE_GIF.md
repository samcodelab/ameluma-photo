# Workspace and GIF implementation

The current reliability fixes and verification are documented in [RELIABILITY_REVIEW](RELIABILITY_REVIEW.md). Earlier validation counts and captures below describe the original implementation, not the updated build.

## Initial architectural review

The MainActor Workspace coordinator owns one source array, explicit selection, editor tabs, batch scopes and saved collages. Platform adapters supply Files/Finder/Photos import and native sharing. ImageProcessor imports private snapshots, downsamples previews, renders shared configurations and validates staged exports. AnnotationRenderer and normalised Annotation geometry are reusable. ProjectDocument schema 4 supports optional additive fields with legacy migration.

Found issues: reconcileVisibleSelection intersected selection with filtered IDs; selected batch targets also used filtered assets. Context menus mostly targeted explicit IDs but had no common group action capture. Selection must intersect existing sources only; workflow operations capture ordered IDs independently of subsequent filters or selection. No second library or selection model is needed.

GIF projects use frame-specific captured processing configurations and source IDs, stable frame IDs, centisecond timing and explicit annotation frame membership. The existing source relink UI repairs missing references. GIF rendering reuses ImageProcessor with bounded source decode and AnnotationRenderer. Image I/O handles native palette encoding; no external codec is introduced. Preview uses the same frame composer and timing as export, with reduced resolution.

## Validation

Baseline Core tests and both platform builds are run before implementation. Final evidence and limitations are recorded below as checks finish.

Baseline: 104 Core tests passed; Mac arm64 and generic iOS Simulator targets built unsigned successfully. Initial restricted attempts could not write compiler/Xcode caches; rerunning with approved cache access succeeded.

## Implemented behaviour

- Workspace replaces the imported-area library terminology. Apple Photos integration names are unchanged. Header-only date/format/orientation details and filename/Vision-label search use existing sources; no catalogue or second selection system was added.
- Selection intersects existing sources, not visible results. Select Visible adds visible IDs. The summary reports hidden selections. Explicit batch inputs, context targets and creation inputs remain stable across filtering/navigation.
- The GIF selection context temporarily uses the same selected-ID set, retaining the previous ordered selection, filters, workflow, scope, active photo, tool and framing presentation. Cancel restores that state. Completed GIFs keep captured source IDs/configurations independently.
- GIFs have stable frame IDs, frame order, duplication/removal, per-frame/group/global timing, deliberate filename/date ordering, Fit/Fill, per-frame crops, canvas/background, text/arrows/rectangles/ellipses/speech bubbles and explicit annotation membership. Until Removed extends to added frames until ended. Frame ranges follow IDs through reordering.
- Source edits render before GIF framing, keeping privacy masks attached to their content. GIF-only overlays render afterwards in normalized output coordinates. Project preview and export share the composer. Preview is disk-backed at reduced resolution; playback uses the exported centisecond timing and a monotonic clock.
- GIF Undo/Redo and grouped crop/annotation gestures are independent of photo history. Current and earlier GIFs save as optional schema-4 data with existing sources; schema-2/3 projects still load. New creations archive previous GIF instructions. Replacing frames preserves frame identity and visibility membership.
- Native Image I/O export renders sequentially with cancellation/progress, decodes every frame to validate dimensions/timing/looping and publishes exclusively. Collision suffixes preserve existing files. Reviewed copies retain complete animation bytes. GIF sharing offers manual encoded-frame inspection; the optional still-image sensitive-content checker and still-image clipboard action are unavailable for GIFs.
- Image I/O loop counts represent total plays. Empirical native-encoding inspection confirmed it writes total-minus-one into the NETSCAPE repeat extension; omitting that extension means Play Once (decoded as loop count 1). Tests cover once, forever and finite looping.

## Limits and engineering decisions

GIFs accept 1–1,000 frames, dimensions 16–2,000 per side, durations 0.1–60 seconds and speed 0.5/1/2× in the interface. Effective durations round to centiseconds with a 0.1-second minimum to avoid player-specific short-delay clamping. Custom finite plays are supported. Third-party GIF players can schedule playback differently.

Optimisation presets set 480/800/1,600-pixel longest edges. Custom dimensions remain available. Native Image I/O performs palette encoding; custom quantisation/dithering is not implemented, and photographic banding is possible. No exact file-size estimate is shown before encoding. Output size is measured afterwards. No external codec or network service was added.

The application retains only bounded-size rendered frames in its own pipeline; Image I/O may retain encoder state. The 24-frame synthetic 24-megapixel-source regression demonstrates functional large-source handling, not a measured peak-memory guarantee or 1,000-frame physical-device benchmark. Preparing many previews uses temporary disk space. Preview files are removed on editor exit/background or cooperative cancellation; abrupt termination can leave temporary files for system cleanup. Private mode also disables the GIF renderer's source thumbnail memory cache; it is not encryption or secure deletion.

GIFs preserve visible photo edits in flattened output, use sRGB and omit copied source metadata. GIF palette limits preclude full photographic colour fidelity. Workspace removal now retains source records required by creations. If a retained file is genuinely missing, use frame replacement or Projects → Relink. Original files are never deleted by workspace removal.

Native layout captures use synthetic photos. Physical iPhone/iPad gestures, Pencil, VoiceOver, energy/memory profiling, real large-collection throughput and cross-player photographic/dithering quality remain manual release checks. Generated layout captures and Simulator tests do not establish those claims.

## Historical validation of a41a4a9 — 16 October 2026

- 110 macOS Core tests passed, including new native GIF roundtrips, once/finite/forever loops, collisions, byte-preserving reviewed copies, individual/global timing, frame identity/order/duplication/removal, annotation membership, fitting, privacy-preserving crops, missing references, cancellation and project migration/persistence. A 24-frame preview/export uses a synthetic 6,000 × 4,000 source.
- 185 iPhone 17 Simulator app-hosted tests passed, including existing editing/batch regressions and new contextual selection, cancel/return, photo-first/action-first GIF entry, append/replace, independent captured edits, GIF history, workspace removal and restoration tests.
- 45 iPad Pro 11-inch (M5) Simulator GIF/workflow tests passed on the final encoder; an earlier 46-test pass also included native compact/adaptive layout captures.
- 21 native Mac tests passed, including native selection gesture adapters and generated-photo layout captures. The final Mac arm64 target built unsigned successfully. Both Simulator test destinations build the iOS/iPadOS application target.
- `git diff --check` passed. No source images, signing identities, App Store records, network entitlements or third-party runtime dependencies were changed.

Reviewed captures: [Mac GIF Creator](screenshots/mac-gif-creator.png), [Phone GIF Creator](screenshots/phone-gif-creator.png), [Phone large text](screenshots/phone-gif-accessibility.png), [iPad-width GIF Creator](screenshots/ipad-width-gif-creator.png). The iPad-width image is a native size-class component capture; it is distinct from the additional actual iPad Simulator test run. Large-text playback controls were corrected after visual inspection. Capture evidence does not replace physical-device gesture/VoiceOver validation.
