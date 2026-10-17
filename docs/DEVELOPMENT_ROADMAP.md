# Development roadmap

## Immediate priorities — 17 October 2026

These priorities supersede older expansion items below. Preserve current features and saved results while improving a focused everyday photo editor.

1. Audit every photo tool entry/exit against one persistent canvas. Consolidate remaining user-visible editor transitions; retain photo, viewport, cached source, pending edits and undo state. Test rapid tool changes and cancelled drafts on all three interfaces.
2. Treat the bird tail/claw example as a failing retouch acceptance case. Retain the original and record stroke geometry and settings for reproducible comparisons. Separate Clone, Heal and structural object removal in implementation and claims. Evaluate a bounded, local reconstruction approach using representative photographic fixtures before choosing an algorithm; do not conceal failures through extra blur. Version new processing so existing strokes retain their output.
3. Measure complete interaction latency: pointer feedback, stroke completion to preview, cancellation and export, including repeated strokes on large images. Isolated kernel timings are insufficient. Profile decode, graph replay, GPU completion and main-thread work before setting optimisation priorities.
4. Standardise nearby tool options, visible selection coverage, keyboard/mouse and pinch/pan behavior, Undo/Redo, failure/retry and Apply/Cancel semantics. Avoid simultaneous duplicate inspectors and floating controls.
5. Validate rendered quality and real interactions across Mac, iPhone and iPad, then save/reopen, preview/export parity and original hashes. Require physical-device checks where Simulator coverage cannot establish performance or Pencil behavior.

The current translated-source Heal remains a foundation, not a completed content-aware removal tool. This roadmap records intended work; it does not claim these gates have passed.

## Existing foundation — retained

Separate native app targets/local Core package; import/browse/preview/resize/crop/rotation; visual framing and shared precision/history; Vision classification/search/framing/review; watermarks/compression/formats/metadata/profiles; safe export/retry/local recovery.

## Everyday editing — implemented foundation

Seven adjustments, conservative Quick Fix, borders/backgrounds/corners/shadows, Compare and processed-output sharing. Contextual inspectors and task-oriented phone home are implemented. Next: guided task-specific settings, measured automatic-correction corpus, larger touch/key polish and richer side-by-side comparison options.

## Creative tools — implemented foundation

Three editable collage layouts, cell framing/source swapping, freeform geometry, titles/captions and shared annotations. Text/basic font/alignment controls and shape/freehand overlays are implemented. Next: direct resize/rotation handles, multi-line text layout, snapping, collage z-order controls and more sophisticated typography/layout rules.

## Privacy — implemented manual workflow

Four real mask effects, three region shapes, manual Crop to Hide, flattened metadata-restricted output, ephemeral manual sharing approval/exclusion and private cache/conceal controls. SensitiveContentAnalysis was researched but not enabled in the unsigned build. Next: signed entitlement/use-case verification, actual permitted-system-policy tests and temporary sensitive verdict handling if approved. Never advertise automatic checking before validation.

## Mac Automations — implemented foundation

Bookmarks, dashboard, recipes/action toggles, FSEvents hints, reconciliation, stable-file/hash checks, safe output, manual review queues, test preview, retry and menu-bar monitoring. Next: heavy-load profiling, external-provider/disk-full/revocation/power-loss tests, transactional publication recovery, user-managed cleanup, scheduler/backoff and optional SMAppService login integration. No daemon or login item was registered.

## Integration — implemented and remaining

Implemented: still-only Live Photo messaging, hash duplicate skip/import-anyway, project copies/open/relink, schema-3 migration, collage history, contextual UI, basic accessibility alternatives and privacy manifest.

Release requirements:

1. Real physical iPhone/iPad/Mac tests at deployment minimums; 48-megapixel sources and 100/1,000/10,000-photo collections. Measure memory/disk/latency/thermal behavior.
2. Complete storage accounting/removal/recovery UI, shared-session concurrency safeguards, provider-compatible exclusive publication and precise interruption deduplication. Audit orphaned owned snapshots and permissions.
3. Validate VoiceOver, Dynamic Type, keyboard-only operation, Pencil/trackpad, contrast, reduced motion, localization and navigation. Add targeted UI automation and annotated interaction recordings.
4. Approve/refine the implemented app icons; finish signing, privacy-required API audit/archive report, App Store privacy/support text, Standard EULA, encryption declarations and universal shared app record. No paid records or submissions without approval.
5. Sensitive analysis only after capability/policy/legal review and real-device checks. Keep manual review usable regardless of entitlement.

The intended price is A$29.99 for one universal purchase; no subscription or IAP exists. Do not commit, push, publish or submit without approval.

Final collage UI interaction/export validation remains blocked by the native UI automation service startup failure. Preserve that verification gap until manually completed; the shared renderer and state/recovery tests pass.

Scoped workflow revision: implemented field-preserving edits, sparse inherited overrides and schema-4 migration, operation-only sharing, active/group selection, explicit framing IDs, processed interaction previews, encoded output proof and profile plans. Next: physical-device gestures/accessibility, performance profiling with many per-photo overrides and profiles, more concise per-field mixed widgets, and persistent workflow/navigation restoration.


### Tabbed Editor update

Completed: library-first navigation, separate batch and editor targets, compact closable photo tabs on Mac; single-photo mobile editing with Back to Workspace, saved tab restoration, contextual Privacy tool and Privacy Review filter. Further work: draggable tab ordering, detachable editor windows and per-tab canvas zoom persistence are not implemented.


### Art collage extension

Implemented: named saved collage tabs, independent session histories, a 74-layout visual gallery, thumbnail source/reference selection, cell and whole-composition shapes, exact-count text/shape tiling, local colour/tone reference mosaics, reuse controls, progress/cancellation and bounded tile rendering. Next: representative physical-device/10,000-tile benchmarks, more fonts and text layout, arbitrary imported silhouettes, semantic matching and more advanced palette matching (only after measurement), detachable/reorderable tabs.
