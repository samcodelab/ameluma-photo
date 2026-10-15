# Cross-platform usability review — 14 October 2026

Reviewed native source, current app screenshots, shared editing state, acquisition, export/review and cleanup boundaries. Design reference: [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) and [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons).

## Changes delivered

- Mac gallery controls remain at the top in empty and populated states. Empty state offers Import Photos. Inspector can be hidden and the window can become narrower when hidden.
- Responsive gallery toolbar removes fixed-height clipping of contextual warnings; phone preview sizing uses a native menu instead of a crowded desktop slider. Extra-large previews fit the available width. Accessibility text sizes use wider gallery cells.
- Select enters a deliberate selection mode with selected export/edit scope; Done preserves that scope. Selecting visible results uses the same state. Scope/count is explicit in inspector and Mac export area. Existing crop overrides remain intact. Resize is distinct from Frame viewing mode.
- Search/filter empty states explain the absence of matches and offer Show All Photos; mobile search can be cleared and filters show the active category.
- iPhone has one import empty state, fewer repeated counts/status messages, quick photo actions that adapt to larger text, and Projects/Clear access from Home and the gallery menu. iPhone gallery scrolling does not activate crop gestures; Refine owns drag and pinch. iPad offers deliberate Reframe thumbnails for its selected image and an inspector only when detail width permits it. Narrow iPad uses sheets/full-screen precision editing.
- PhotosPicker acquisition is tracked, progressive and cancellable; indexing starts afterward. Cancelled acquisition retains completed photos and does not automatically open a new editor. Live Photo still-only messaging remains after import.
- Crop navigation, rotation, comparison, zoom and watermark sliders have more descriptive accessibility labels. Mobile gallery action menus have at least 44-point target frames. Numeric precision controls remain alternatives to gestures.
- Classification scheduling uses a pending-ID set, lookup and forward cursor instead of repeatedly removing/scanning a large source array. This removes quadratic array work; it does not establish a throughput guarantee.
- Original-preserving clear/close, final-output-only sharing and capability-gated sensitive review remain in place. No networking, analytics or dependencies were added by this review.

## Visual evidence and limits

Screenshots use eight synthetic landscape/portrait layout fixtures, not user photographs. Mac dark appearance and iPhone/iPad light appearance were inspected; iPhone accessibility-large text revealed wrapping, which was corrected with wider tiles and a photo-actions menu. Screenshots are in docs/screenshots. Normal and accessibility text were checked on Simulator. Native UI automation could not bind reliably to the Mac app; interactive click-through, VoiceOver traversal, keyboard focus, multitasking transitions and physical touch/pointer/Pencil behaviour still require hands-on validation.

Debug-only -FramepebbleReviewRoot <path> selects an isolated workspace and -FramepebbleReviewGallery opens the phone gallery for layout inspection. These switches do not exist in Release. Xcode Debug configurations now explicitly define DEBUG. Test suites use injected fixtures for state testing and real shared processing for output verification.

## Remaining release work

- Run physical-device/VoiceOver/keyboard and narrow iPad multitasking checks, including direct reframing, annotation manipulation and native system pickers/share sheets.
- Measure large real NAS batches, launch recovery, memory/CPU and cancellation latency; the 50,000-record test is metadata-state validation, not a throughput measurement.
- Sensitive Content Analysis is still capability/policy gated under local-only signing. No real detector availability or child-policy flow is certified by fixture tests.
- Public privacy/support URLs and distribution/device provisioning remain outstanding. This review does not guarantee App Store approval.
- The supplied photography concepts remain visual inspiration. Native system controls adapt to installed OS appearance; custom icons, final typography tuning and representative photo-based screenshots should follow interaction validation.

## Final verification and changed files

Mac app build and strict local development signature verification passed. iOS Simulator app-host suite passed 100 tests; macOS app-host suite passed 18 tests. This includes existing original-preservation, safe cleanup, processing, browser-drop/automation and privacy-review regression coverage plus selection-scope/override preservation. Physical-device gestures and live automatic sensitivity analysis were not tested.

Changed implementation: Apps/Shared/Workspace.swift; Apps/macOS/FramepebbleMacApp.swift; Apps/iOS/FramepebbleIOSApp.swift; SharedUI/LibraryViews.swift; SharedUI/FramingViews.swift; SharedUI/Inspectors.swift; Tests/WorkspaceTests.swift; tools/generate_project.py; generated Framepebble.xcodeproj. Updated README, architecture, bundled help, test plan and this review. Synthetic screenshots: polished-mac.png, polished-iphone.png, polished-ipad.png and polished-iphone-large-text.png.

## Continued polish audit — four-workflow foundation

Current self-assessment: 8/10, below the requested completion threshold. Workflow scope, edit preservation and operation-specific sharing now have meaningful regression coverage. Remaining quality gates include live visual inspection of the latest adjustment controls, physical touch/accessibility testing and smoother direct manipulation across canvas tools. This is a working assessment, not evidence of professional-editor parity or release readiness.

Adjustment sliders now have inline numeric entry with finite range clamping, per-control Mixed indicators, and compact reset buttons that remain available for mixed selections even when the representative value is neutral. Both macOS and iOS Simulator application builds pass. The latest native UI inspection attempt returned cgWindowNotFound; a stack sample showed the isolated synthetic review process idle in the AppKit event loop rather than blocked processing. Visual verification of these new controls remains pending. Earlier synthetic workflow verification remains recorded separately in TEST_PLAN.md.

## Single-canvas Photo Editor audit — 15 October 2026

Added explicit Adjust, Crop & Frame, Resize, Annotate, Hide Something and Watermark & Format controls. Crop gestures require the crop tool; ordinary adjustments cannot accidentally reframe the photo. Wide layouts use the main canvas rather than a duplicate miniature precision preview. Annotation/privacy entry preserves the requested tool. Crop inputs show percentages and reject non-finite values, while filmstrip navigation keeps the current photo visible and respects Reduce Motion.

Native NSHostingView layout attachments use generated safe images and never capture the desktop or user projects. They exposed duplicate numeric-field labels, now removed. Offscreen AppKit capture does not reliably composite native button materials/text, so these attachments establish content geometry and labels rather than final live appearance. A snapshot harness ownership crash was fixed with explicit non-releasing test-window lifetime; the rerun passed. Live final appearance and interaction review remains necessary. Current working assessment: 8.3/10, still below the completion threshold.

## Final adaptive review — 16 October 2026

The final native hierarchy review covers compact phone, accessibility sizes including the largest size, and Mac standard/minimum windows in light/dark. Fixed two-row photo navigation, accessible Tools menus, full-width numeric fields, a compact large-text gallery header, More overflow, visible framing reset, wrapping-safe transfer actions and a semantic native workspace background. The final captures now render native Mac controls correctly; this resolves the earlier offscreen-compositing limitation for these captures. Self-assessment reaches 9/10; see UI_UX_COMPLETION_AUDIT.md for the criteria, evidence and release-validation limits.
