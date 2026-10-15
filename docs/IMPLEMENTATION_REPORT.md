# Implementation report — 14 October 2026

## Outcome

The initial cross-platform foundation now has a real visual framing workspace, native Vision analysis/search, watermarking, advanced output controls and durable session/retry state. This is a development build with substantial Phase 1–4 functionality; commercial-release Phase 5 is not complete.

## Features and decisions

- Bounded native Mac workspace with library sidebar, Browse/Frame/Compare grid and draggable/collapsible precision inspector. Phone library, full-screen precision editing and transform/export sheets; adaptive iPad sidebar/grid/inspector.
- One shared affine layout and normalized crop model for direct manipulation, precision state, subject guides and exported geometry. Continuous gestures form one Undo transaction. Aspect-only overrides follow batch width and keep inheriting batch quality/watermarks; explicitly scoped processing overrides stay independent.
- Native classification and revision/fingerprint index, visible/selected thumbnail priority, actual label suggestions/search, multi-selection and search-scoped operations. Spatial Vision requests remain separate from label classification. Fallback/review behavior is deterministic and manual overrides are protected.
- Fit/Fill/Stretch/Canvas/proportional sizing, custom pixels/presets, prevent-upscaling, quarter turns/flips/straightening, text/image/tiled watermarks, native codec capability checks, bounded target encoding, RGB colour/metadata policies, saved/multiple profiles and safe naming.
- One serial full-resolution renderer, one serial analyzer, 32 MB/128-entry thumbnail cache, view-size previews, source/text-stamp allocation guards and cooperative cancellation.
- Validated, exclusive staged export, stable request IDs, partial error handling, retained completed results, pending-request retries and versioned local source/index/edit/preset storage. Container moves rebase private references. Photos change blocks use an explicitly nonisolated Sendable adapter.

## Modified/added files

- `Packages/FramepebbleCore/Sources/FramepebbleCore/Models.swift`, `ImageProcessor.swift`, `FramingState.swift`, `FramingLayout.swift`: expanded models, history, geometry, transforms/encoding and safety.
- `AutoFraming/VisionAnalyzer.swift`, `Search/Classification.swift`: native analysis, search abstractions/index and actual proposals.
- `Watermarking/WatermarkRenderer.swift`, `Persistence/ProjectDocument.swift`: shared stamps, versioned storage and export requests.
- `Apps/Shared/Workspace.swift`: authoritative state, scopes, history, async indexing/framing, source rebasing, persistence and retry coordination.
- `SharedUI/LibraryViews.swift`, `FramingViews.swift`, `Inspectors.swift`: native visual workspace and functional controls.
- `Apps/macOS/FramepebbleMacApp.swift`, `MacZoomCapture.swift`: platform import/export, native workspace and modifier-scroll adapter.
- `Apps/iOS/FramepebbleIOSApp.swift`, `PhotoLibraryExporter.swift`: adaptive workflow, orientation configuration, add-only saving and lifecycle handling.
- Shared/app tests, `tools/generate_project.py`, Xcode project/schemes: new integration coverage, adapter references, explicit orientation and universal Mac Release architecture settings.
- `AGENTS.md`, `README.md` and documentation: consolidated direction, accurate specification/architecture/roadmap/test evidence/help/privacy/provenance/visual review and real screenshots.

## Verification

- macOS arm64 Debug build passed; actual startup, import, classification, direct drag, numeric refinement, Undo, Smart framing, relaunch and inspector resize/collapse/reopen were exercised.
- macOS Release build passed for **arm64 + x86_64**, verified with `lipo`.
- Generic iOS Simulator build passed, with iPhone/iPad target families and explicit supported orientations.
- **35 shared tests passed on Mac**.
- **45 tests passed on iPhone 17 Simulator**, including all shared tests, interface-state/container-migration/multi-profile/100-image tests and an actual Photos save regression. No Photos integration skip occurred in this run.
- Native PhotosPicker selected only the public-domain QA photo. It indexed locally, restored after reinstall and completed a real 20-megapixel-to-square export/save to Simulator Photos.
- Synthetic 100-image batch validation completed in roughly 1.3 seconds on this host; fixtures were 80×40 with 256×256 outputs. This is not a physical-device or large-photo throughput claim.
- Source audit found no app networking clients/endpoints and no forbidden UI/Photos framework imports in Core. No third-party runtime dependency/model was added. Sources remained byte-identical in preservation/collision tests. No commits, pushes or App Store records were created.

## Remaining and known limits

Physical-device/minimum-OS execution, large-image/large-collection peak memory and thermal profiling, full accessibility/localization, Pencil/trackpad/keyboard QA, signed sandbox/distribution checks, app icons and release metadata remain. The current project is one autosaved session with local copies, not a document browser/storage-management/relinking UI. External destinations are reselected after relaunch; bookmark-aware per-profile destinations are future work. A publication-to-ledger crash window can leave a valid unrecorded output and cause safe numbered duplicates on retry. Provider-specific exclusive rename and Photos format support need broader testing.

Vision accuracy is not guaranteed; foreground-mask integration and arbitrary local semantic search are not implemented. Watermarks reappear in full composites after active framing gestures. WebP encoding remains hidden where ImageIO lacks a registered encoder. Supported dictionary metadata policies do not guarantee anonymity or removal of every embedded hint.

Next: profile real device collections, complete storage/recovery and destination adapters, refine interaction/accessibility/density, build a Vision ground-truth corpus, then finish signing/App Store preparation. Universal purchase requires consolidating the provisional identifiers into one bundle ID before registration under current Apple guidance.

See `VISUAL_REVIEW.md` and `docs/screenshots/` for the actual interfaces and comparison with the supplied concepts.
