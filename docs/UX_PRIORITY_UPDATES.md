# High-priority workflow improvements

Implemented following the October 2026 workflow review, without changing the project schema or modifying original images.

- Batch Edit displays an explicit editing-scope heading above the gallery and in the inspector. When All is active alongside a selection, the gallery states that all imported photos are targeted and offers Edit Only Selected Photos.
- Reset Changes separates Restore Original Appearance (native size, visual edits removed, output/metadata protection retained), Reset Batch Settings (shared defaults only) and Remove Individual Overrides (inherit current shared settings). Confirmations describe the whole-library effect, privacy-mask removal and checked export profiles. Every operation is one photo-history step. Existing legacy reset implementation remains for compatibility but is no longer the main reset action.
- Privacy/annotation drafts retain the open-photo strip, with the Mac/iPad sidebar remaining visible. Document switching is disabled until Apply/Cancel. The shared strip is an installed SwiftUI view so compact/accessible presentation follows its actual environment.
- Single-photo Crop & Frame shows the full transformed and adjusted source with a movable crop rectangle and eight draggable boundary handles. Freeform resizing retains requested output width and derives height. A shared Core inverse maps the source-pixel selection into existing normalized crop state; batch thumbnails continue using fixed output frames. Crop view explicitly omits masks, annotations, watermark and canvas decorations; Edited preview shows their final processing. Review overlay placement after reframing. Numeric controls remain available.
- Collage creation exposes Photo Layout, Shape Collage, Text Collage and Photo Mosaic. Art choices open their setup controls directly. Reference selection is presented from the active setup sheet. Generation retains existing cancellation/progress behaviour.
- The layout gallery defaults to Apply to Current Collage, with a separate Create New Collage choice. Applying a layout preserves document identity, uses existing shared template rendering and supports composition Undo.

## Remaining UX work

These changes do not implement medium-priority tab thumbnails/reordering, saved collage photo thumbnails, freeform collage transform handles, a unified per-document undo model or the broader iPhone bottom-sheet redesign. Privacy/annotation still use a reversible draft sub-editor, now retaining document context. Crop boundaries are freeform rather than aspect-locked; numeric aspect presets remain available. Manual mouse/touch, VoiceOver and physical-device validation remain necessary; automated native rendering is not a usability study.

## Validation

- Shared package: 99 tests passed (`.build/priority-core-tests.log`).
- iOS Simulator full app-host suite: 161 tests passed (`.build/priority-ios-tests-final.log`).
- Mac full app-host suite: 21 tests passed (`.build/priority-mac-tests-final.log`).
- After visual corrections: 27 focused iPhone layout/workflow tests and the Mac native layout test passed (`.build/priority-ios-layout-final.log`, `.build/priority-mac-layout-final.log`).
- Final macOS and generic iOS Simulator builds succeeded (`.build/priority-mac-build-final.log`, `.build/priority-ios-build-final.log`).
- Inspected generated native captures of crop handles, retained draft document tabs, collage creation and compact iPhone controls. Corrected outdated crop guidance, respected Guides/Subjects toggles and reduced mobile creation controls to one compact row. No physical-device or live pointer/touch validation is claimed.
- Project schema unchanged; regression suites include existing migration, original preservation and sharing isolation coverage. No dependencies, networking, commits or pushes added.
