# Test plan and verification evidence

## Automated tests

Run `swift test --package-path Packages/FramepebbleCore` on Mac. Run the `FramepebbleCoreiOSTests` app-hosted scheme on an installed Simulator with parallel testing disabled. The project generator includes every shared test file plus `Tests/WorkspaceTests.swift`. Tests use generated real raster inputs, not fabricated processing results.

Initial coverage was 35 shared tests and ten interface-state/integration tests. Latest toolbox coverage is 55 shared tests, 17 workspace tests and five native Mac automation tests.

| Area | Evidence |
|---|---|
| Geometry | Landscape/portrait/square, Fit/Fill/Manual/Stretch/Canvas, resize bases, extreme ratios, no upscaling, normalized drag equivalence, clamping and zoom limits |
| Orientation | All eight EXIF orientations, clockwise/counterclockwise pixel order, flipping/straightening, rotated framing intent |
| History/state | Shared grid/precision configuration, gesture grouping, Undo/Redo, explicit reset, scope isolation, batch quality/aspect preservation |
| Vision/search | Real native classification and framing requests, serial concurrent requests, cancellation, centred fallback, subject-union boundaries, actual label filtering/ranking, missing labels and fingerprint invalidation |
| Watermark | Nine anchors, relative margins, text raster output, image alpha/opacity/rotation, tiling and reduced-preview/export normalized placement |
| Formats/colour | Every registered configured encoder, decoded type/dimensions, PNG transparency, white JPEG flattening, sRGB/P3 preservation/conversion |
| Compression/metadata | Actual bounded quality search on deterministic noise, infeasible target rejection, no publication on failure, supported GPS policy checks |
| Files/export | Original byte preservation, aliases/symlink collisions, safe names, invalid/missing sources and destinations, cancellation cleanup, partial failures and retry exclusion of completed requests |
| Persistence | Schema roundtrip, additive field defaults, unknown-version rejection, missing references, restored edits and pending export work |
| Batch | 100 real generated-image exports, progress/completion count, validated output count, no pending requests and original preservation |

## Environment and results

Foundation verification used Xcode 27.0 (27A266a), Swift 6.4, macOS 27 SDK and iOS 27 SDK with iOS 26.5 Simulator runtime. Deployment targets remain macOS 15 and iOS/iPadOS 18. Both app builds disable signing for development verification.

- macOS arm64 application build: passed.
- Generic iOS Simulator application build, including the iPad target family: passed.
- Shared package tests on Mac: 35 passed.
- Shared + interface-state tests on iPhone 17 Simulator: 45 passed.
- The synthetic 100-image test completed in approximately 1.3 seconds on this Simulator host; this uses 80×40 source fixtures and 256×256 exports and is not a real-photo/device throughput claim.

Logs/result bundles live under ignored `.build/`. Fresh final logs use `final-mac-build.log`, `final-ios-build.log` and `final-ios-tests.log`. An earlier default-compute Simulator Vision run failed with “Failed to create espresso context”; the supported-CPU selection fixed it. Some old diagnostics were written after later runs; final verification uses separate logs and its own `.xcresult` bundle.

## Native UI checks

Mac: imported a recursive folder containing a CC0 20-megapixel dog photo. Real Vision labels included Dog/Retriever/Canine. Applied a square preset, switched to Frame, opened precision controls, changed numeric zoom and dragged the thumbnail. The precision position changed with the drag, and Undo restored it. Smart produced a real proposal. Relaunch restored the source/settings/index. Initial and updated export flows use native folder panels.

iPhone/iPad: standalone apps installed/launched. iPhone PhotosPicker imported the selected CC0 photograph with item-only access and local classification completed. Explicit supported orientations and actual device idiom keep the phone workflow mobile in landscape. Further mobile interaction findings and final screenshots are recorded in `VISUAL_REVIEW.md`.

Screenshot/source provenance is in `QA_ASSETS.md`. Captured interfaces are development screenshots, not marketing renders.

## Required release validation

- Physical devices: 48-megapixel sources, 100/1,000/10,000 collections, peak resident memory, disk consumption, thermal behavior and full gesture latency.
- Denied/revoked Photos additions, accepted/rejected file formats, Photos save failures and retry/share availability.
- Files/iCloud/local/external providers: directory access, offline data, missing sources, disk-full/disconnected volumes, exclusive publication support and collision races.
- Signed macOS sandbox and physical iOS signing; minimum-OS execution in addition to newer runtime compilation.
- Abrupt termination between publication and ledger save; source relinking and session corruption/recovery.
- Vision photo corpus with real dogs/cats/people/multiple subjects, edge subjects, false positives, classifier revisions and segmentation experiments. No calibrated accuracy claim yet.
- VoiceOver, Dynamic Type, keyboard-only operation, pointer/Pencil, reduced motion, contrast and localization.
- Distribution/Icons/App Store metadata/privacy-manifest audit and universal-purchase identifier consolidation.

The final native Photos queue-boundary regression test performed an actual Simulator save with add-only permission and passed (not skipped in this run). The live 20-megapixel CC0 photo was processed and saved successfully after moving the Photos change block into an explicitly nonisolated, Sendable platform adapter. Previous MainActor-inherited change blocks crashed on the framework queue; this is resolved in the final build.

## Toolbox extension verification

The latest extension retains the original 35 shared regressions and ten workspace regressions. New coverage exercises neutral/bounded/combined adjustments, real Quick Fix, patterned-image blur/pixelation/frosted effects, opaque/freehand mask coverage, flattened output/source preservation, metadata restrictions, annotations/canvas rendering, eight-cell collage geometry/rendering/persistence, cancellation, private cache bypass, SHA-256 duplicate handling, timed transfer stability, disabled recipe actions/native format validation, source-orientation retention, manual review approval revocation, schema-2 migration and project relinking/collage history.

Native `FramepebbleMacTests` exercises real output publication, original byte preservation, restart deduplication, explicit review withholding/approval, missing destination reauthorisation/recovery, corrupted-file failure deduplication, loop rejection and live running monitoring without manual scans. Stable files must remain unchanged for at least two seconds before becoming candidates. Automation fixtures use real raster files and temporary isolated folders.

Current commands additionally include:

```sh
xcodebuild -project Framepebble.xcodeproj -scheme FramepebbleMacTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Framepebble.xcodeproj -scheme FramepebbleMac -configuration Release -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Framepebble.xcodeproj -scheme FramepebbleiOS -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Latest results and limitations are recorded in `TOOLBOX_IMPLEMENTATION_REPORT.md`; ignored logs are `toolbox-core.log`, `toolbox-mac-tests.log`, `toolbox-ios-tests.log`, `toolbox-mac-release.log`, `toolbox-ios-release.log`.

Live QA found and resolved a mobile boolean-sheet capture bug: completed review URLs were initially stale/empty. An item-based presentation payload now carries the exact rendered files. Live verification confirmed a masked thumbnail, exclusion revoking share actions, explicit reapproval and successful reviewed Photos saving. The Mac live workflow processed a newly copied 20-megapixel CC0 image to 1024×1024 JPEG, with unchanged source SHA-256. The QA workflow was paused afterwards; completed output remains under ignored `.build/automation-QA/Output`.

Automatic SensitiveContentAnalysis, physical-device performance, signed sandbox behavior, launch at login and comprehensive accessibility/provider/power-loss validation have not been verified. Passing Simulator tests does not establish physical-device interaction or memory behavior.

Latest full results: 55 shared Mac tests, 72 Simulator tests and five native Mac automation tests passed with zero failures/skips. The strengthened 100-image 1024×1024 JPEG test took approximately 6 seconds. The final collage UI smoke test was blocked by the native automation service failing to start; backend eight-cell rendering/persistence and completed-output recovery are tested.

## Browser and network import regression coverage

BrowserDropTests covers native provider bytes/URLs, fallback representations, mocked bounded URLSession responses, unsupported content and unresponsive-provider cancellation. SourceImporterTests covers incremental availability, independent thumbnail rendering, changed inputs, partial copies, cancellation and symlink/recursive destination safety. WorkspaceTests verifies editing before a 50-image import finishes and accurate duplicate progress/original preservation. Real Safari/Chrome drop gestures and homeNAS throughput/disconnection remain manual QA.

## Incremental acquisition and privacy review update

See [incremental import](INCREMENTAL_IMPORT.md) for publication and checkpoint scheduling, [privacy review](SENSITIVE_CONTENT.md) for transient state and capability gating, and [signing](SIGNING.md) for verified local-signing limits. Regression coverage includes editing during acquisition, 50,000 synthetic gallery records, temporary findings/filtering, source invalidation, manual flags, and sharing approval invalidation. Automatic Apple detection and actual large NAS throughput are not validated by these fixtures.

Verified 14 October 2026: iOS Simulator app-host suite passed 95 tests; macOS app-host suite passed 18 tests. macOS development-signed build succeeded and passed strict signature validation. No physical-device, live Sensitive Content Analysis, or 50,000-real-file NAS throughput validation was performed.

Cleanup regression tests verify original bytes, reimport after clearing, saved-project source retention, refusal to clean when a saved project is unreadable, and exclusion of symlinks, external paths and unknown filenames. Preview size changes display only.

Preview/cleanup verification (14 October 2026): 69 shared-package tests passed natively on macOS, 99 app-host tests passed on iOS Simulator, and the development-signed Mac app built successfully. No physical-device or automated UI interaction validation was performed for these controls.

Cross-platform polish validation: 100 iOS Simulator and 18 macOS app-host tests passed; final Mac development build and strict signature validation passed. Selection-mode tests verify target scope and retained crop overrides. Visual inspection used isolated synthetic fixtures on Mac, iPhone/iPad Simulator and iPhone accessibility-large Dynamic Type. Native interaction automation was unavailable; physical-device/VoiceOver/keyboard/multitasking gesture checks remain manual release requirements. See UX_REVIEW.md and docs/screenshots/polished-*.png.

Hide Something regression coverage: multi-area Pixelate/Frosted deletion and Undo/Redo, gesture coalescing, cancellation restoring an existing baseline, annotation deletion, private draft isolation, atomic Apply/global Undo, concurrent-change rejection and flagged-gallery/context-editor routing. Real Mac UI checks were performed using synthetic fixtures; Escape cancellation was confirmed by reopening with zero masks.

Main-workspace privacy-editor coverage adds preview-scale-independent resizing, fixed opposite edges, rotated resizing, extreme boundary clamping and invalid viewport handling. Mac native UI verified consecutive Draw operations without Add Area, Select handles increasing width/height, Delete and closing the workspace editor without applying the draft.

## Direct editor verification (14 October 2026)

Final checks passed: 78 native Core tests, 112 iOS Simulator Core/workspace tests, and 18 macOS app-host tests. Both applications compiled; the local Apple Development Mac build and strict signature verification passed. Synthetic-image Mac interaction verified rotation-handle dragging and native Undo, keyboard deletion and Undo restoration, consecutive Draw, eight-handle resizing, Apply and Cancel/Escape/Close draft isolation. Physical iPhone/iPad gesture validation remains outstanding. See EDITOR_COMPARISON.md for remaining interaction gaps.

## Four-workflow and scoped-edit regression verification — 14 October 2026

Final runs passed: 86 shared-package tests on macOS, 128 iOS Simulator app-host tests, and 19 macOS app-host tests, with zero failures. Both application targets built; the Mac build used the existing local Apple Development identity and passed strict code-signature validation. No registration or provisioning changes were made.

New coverage includes field changes preserving distinct crops/dimensions/masks/annotations, mixed-value assignment, scoped inheritance, schema-2/3 migration to schema 4, explicit category copying, active-versus-selected selection and filtering, section changes, framing without scope mutation, operation-only sharing under partial/total failure, 5 inputs producing 15 validated files across 3 profiles, frozen running-export counts, and encoded-preview/export consistency. Native Mac event tests cover modifier selection.

Actual Mac inspection used eight synthetic fixtures in an isolated project and automation store. Verified Command-click, Shift-click, Command-A, section switching preserving the explicit batch, a large processed Photo Editor preview, category-copy selection, and final-resolution encoded proof (1600 × 1200 JPEG). A magazine collage with eight sources and a title produced one reviewed PNG; subsequent Photo Editor sharing contained only its one new photo; batch sharing contained only its eight new outputs. The paused automation editor exposed input/actions/output/review configuration without enabling publication. Existing automation tests exercise monitoring, stability, review, restart deduplication and retry.

Physical iPhone/iPad interaction, VoiceOver, large real NAS collections, and final release-signing/App Store validation remain outstanding. Mixed-value controls currently show a mixed-field summary with a representative value rather than a separate indeterminate state in every widget.

Canvas nudging follow-up: 88 Core tests and both application builds passed. New regression tests verify grouped repeat-key Undo/Redo, cancellation, mask/annotation movement, boundary clamping, invalid input rejection and preservation of unrelated edits. Native keyboard and VoiceOver interaction validation remains pending.

The updated iOS Simulator suite passed 130 tests with zero failures; the final Mac keyboard-modifier follow-up build passed. No live key/VoiceOver validation is inferred from these results.

Proportional resize follow-up: 90 Core tests and both application builds passed. New tests cover rotated opposite-corner anchoring, preview-scale independence, edge-handle proportional scaling and extreme boundary clamps. Live gesture review remains pending.

## Library-first navigation — 15 October 2026

Both app builds passed. The iOS Simulator app-host suite passed 135 tests and the Mac suite passed 19 tests, with no failures. Added regression coverage checks gallery entry from Photo Editor, retained masks/crops/batch IDs, empty implicit export targets during browsing, explicit single-photo opening, return to the previous batch framing view, category filtering, and privacy editor entry without changing collage state. Actual UI inspection of this revision has not been completed; no physical-device validation is claimed.

## Explicit Photo Editor tools — 15 October 2026

The iOS Simulator app-host suite passed 137 tests and the Mac suite passed 20 tests, including the native layout harness. New workspace regressions cover explicit crop gating, switching inspector tools without changing edits or scope, and annotation/privacy starting-tool intent. Native offscreen attachments cover library, Adjust, Crop & Frame and Annotate at 1280 × 820 using generated safe images. Inspection caught duplicate field labels, which were fixed. These offscreen captures do not reliably composite AppKit button materials/text and are not live interaction screenshots. The harness initially crashed on test-window teardown; explicit non-releasing window ownership fixed it and the full rerun passed. Final live keyboard, gesture, appearance and physical-device review remains outstanding.

## Final adaptive layout verification — 16 October 2026

Final full suites passed: 90 Core tests, 138 iOS Simulator app-host tests and 20 Mac app-host tests, zero failures. Native view captures inspect light/dark phone layouts, accessibility text through the largest size, and Mac 1280×820/1040×700 layouts. The largest-text phone tests verify that source-photo pixels retain meaningful visible area, preventing a toolbar-only screen. New captures and the final assessment are linked in UI_UX_COMPLETION_AUDIT.md. The synthetic offscreen Mac harness initially needed explicit window lifetime and semantic background fixes; final captures include visible native controls. These are rendered component hierarchies, not physical-device or live gesture certification.

Final gate: macOS, generic iOS Simulator and the existing local Apple Development Mac build all succeeded; strict signature verification passed. Final native/Simulator suites remained at 20/138 passing tests after mobile handle hit-area adjustments. No registration, provisioning update, commit, push or submission was performed. See UI_UX_COMPLETION_AUDIT.md for the final 9/10 self-assessment and explicit release-validation limits.


## Tabbed Editor navigation (16 October 2026)

Regression coverage now includes unique tabs, separate gallery focus and batch selection, library filters independent of open tabs, active-tab-only export targets, retained edits after closing, last-tab return to library, per-tab runtime tool context, optional project tab-state round trips and stale/duplicate tab-ID filtering. Privacy entry opens the clicked editor tab, preserves batch membership/scope, and blocks tab/workspace navigation during an unfinished overlay draft. Existing project documents without tab fields decode with no open tabs and unchanged edits.

Native Mac layout tests render three photo tabs with safe generated sources. iPhone native layout tests render the Open Photos switcher at standard and accessibility text sizes. Reviewed captures: [Mac tabs](screenshots/mac-editor-tabs.png), [iPhone open photos](screenshots/phone-open-photos.png). These are native view renders, not physical-device testing.

Validation: macOS build and iOS Simulator build succeeded. Mac app-host suite: 20 passed, zero failures. iOS app-host suite (including shared Core): 141 passed, zero failures. Logs: `.build/editor-tabs-final-mac-build.log`, `.build/editor-tabs-final-ios-build.log`, `.build/editor-tabs-final-mac-tests.log`, `.build/editor-tabs-final-ios-tests.log`. Physical iPhone/iPad validation and live assistive-technology interaction were not performed in this update.


## Ameluma Photo branding

Mac product/display name is Ameluma Photo; iPhone/iPad product/display name is Ameluma. App-hosted identity tests verify CFBundleDisplayName, CFBundleName and unchanged Debug bundle IDs on both platforms. Both builds succeeded; 21 Mac tests, 142 iOS tests and two Python release-helper tests passed. Internal module names, legacy storage paths and project formats are unchanged. New app output paths are `.build/mac/Build/Products/Debug/Ameluma Photo.app` and `.build/ios/Build/Products/Debug-iphonesimulator/Ameluma.app`.


## Restore Original

The active-photo regression starts with inherited batch exposure, rotation, square cropping, watermark, privacy mask and annotation. Restore removes visual edits for the requested active photo only, renders at the source’s native 80×40 dimensions, retains format/quality/metadata protection, leaves batch/other-photo settings unchanged, and verifies Undo/Redo plus byte-for-byte source preservation. Full suites passed: 143 iOS tests and 21 Mac tests. Responsive native layout checks cover standard/small Mac windows and compact/accessibility iPhone layouts. Restore confirms before removing masks; Original remains a comparison-only toggle.


## Crop-only full-image reset

Added regression verifying a zoomed square crop can return to the complete oriented source at native dimensions, retain exposure/rotation/watermark/masks/annotations/encoding, remove legacy dimension derivation, preserve batch scope and other photos, and Undo/Redo without changing source bytes. A follow-on zoom retains the restored viewport dimensions. Full suites: 144 iOS and 21 Mac tests passed. The action reads orientation-aware source dimensions through the shared processor before committing, and discards the request if the photo/configuration changes while awaiting identification.


## Visible Undo History and whole-library reset

147 iOS app-host tests and 21 Mac tests passed. New coverage verifies named history steps, moving backward/forward without losing redo, discarding only the redo branch after a new edit, the 80-step bound, full reset of inherited batch settings plus hidden individual edits, and single-step Undo/Redo of that reset. Library sources, favourites, profiles and collage remain intact. Reset clears stale framing proposals. Native Mac captures cover History/Reset controls and the timeline; iPhone captures include accessibility text size. Follow-up native layout checks verify the timeline explanation and session limitations scroll with the entries instead of truncating at large text sizes. Both application builds succeeded. History is in-memory session state; reopening retains edits but starts a new timeline.


## Collage tabs, template gallery and art generation

Final validation: both application builds succeeded. Standalone FramepebbleCore: 98 passed; iOS app-host suite (including Core): 157 passed; Mac app-host suite: 21 passed. No failures. Logs: `.build/collage-core-tests.log`, `.build/collages-ios-tests.log`, `.build/collages-mac-tests.log`, `.build/collages-ios-build.log`, `.build/collages-mac-build.log`.

New coverage exercises all 74 template IDs with 37 sources, preserved cell crops/IDs, exact 100-cell circle/diamond/heart/HELLO partitions, circle/heart alpha clipping, 1,000-tile heart and photomosaic rendering, spatial red-left/blue-right reference matching, disabled-reuse uniqueness, cancellation, original-byte preservation, optional-field/legacy decoding, closed-composition recovery, independent tab histories and native Undo routing. Native Mac captures show two tabs, a rendered HELLO composed of 100 generated-photo tiles and the template gallery; iPhone captures show the adaptive switcher and gallery. Captures live under ignored `.build/collages-*-captures`, not in Git. Source/reference pickers use lazy thumbnail grids. Physical-device scale, native gesture/VoiceOver interaction and representative 10,000-tile throughput remain release validation.

## High-priority workflow review follow-up — 16 October 2026

New regressions exercise purpose-specific reset behaviour (native-size original appearance versus batch defaults versus inheritance), retained profiles, direct crop boundary inversion for landscape/portrait sources, crop changes preserving masks/annotations/adjustments and surrounding batch scope, and applying collage layouts without creating a new document. Existing native layout captures cover the shared photo-document strip, crop boundaries, batch scope/reset controls and collage creation choices. Native captures use generated safe photos, not the user’s library. Physical touch/VoiceOver and live crop-handle interaction still require device/manual validation.

Validation: Core 99/99, full iOS Simulator app-host suite 161/161, full Mac app-host suite 21/21. Following capture-driven visual corrections, 27 focused iPhone layout/workflow tests and the native Mac layout test passed. Final Mac and iOS Simulator app builds passed. Logs use `.build/priority-*`; detailed results and remaining UX limits are in `docs/UX_PRIORITY_UPDATES.md`.

## Comparative-review implementation follow-up

New regressions cover stale Quick Fix merging and whole-operation Undo, cancellation before analysis, source/collage privacy review persistence, relevant-input composition identities, constrained crop handles, fixed output dimensions, direct collage geometry, source replacement/swapping, tab ordering/Close Others, fixed batch inputs across filtering, project metadata round-trip, safe filename examples and read-only source-storage accounting. Native layout captures retain the largest-text photo visibility assertion and include regular/narrow iPad-width component arrangements. See REVIEW_ACTIONS.md for completed versus partial findings and release-validation gaps.
