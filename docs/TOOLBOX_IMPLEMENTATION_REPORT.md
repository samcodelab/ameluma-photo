# Everyday toolbox implementation report

## Existing functionality retained

The repository already contained native Mac/iPhone/iPad apps and one local Core package; multi-import, thumbnails/preview, resize/crop/rotate/flip, visual Frame/Compare/precision state, Undo/Redo, Vision framing/search/review, watermarks, native formats/compression/metadata, profiles and safe export/recovery. It was extended in place. No commits, pushes, store records, submissions or developer agreements were made.

## New implementation

- Seven bounded Core Image adjustments; conservative lighting/colour Quick Fix plus native automatic/straightening suggestions. Neutral/per-control/all-adjustment resets, existing history and downsampled preview/export definitions are shared. Editing automatically exposes Frame preview; the compact adjustment sheet has a processed-photo preview.
- Borders, rounded corners, backgrounds and basic shadows; contextual inspectors and five-action iPhone home; native Mac File/Photo menus and rotation shortcut.
- Three editable collage layouts: Classic Grid, Magazine, Freeform. Cell source swapping/add/remove, shared crop/drag/zoom, freeform geometry/rotation, spacing/canvas/background/borders/corners/shadows, title colour/titles/captions. Core renders originals sequentially. Collage history, cancellation and durable completed-output references are implemented.
- Shared normalized text/arrow/line/rectangle/ellipse/freehand annotations. Basic fonts/bold choice/alignment/colour/opacity/stroke controls; area dragging and numeric alternatives. Text/captions reuse CoreText stamp infrastructure.
- Rectangular, elliptical and freehand privacy areas with real opaque cover, Gaussian blur, pixelation and frosted effects. Crop to Hide opens manual precision framing with the stricter metadata policy. Masked/private exports omit copied source metadata and flatten rendered pixels. Export profiles cannot discard authored masks/annotations; framing reset retains other edits, while explicit Reset All is clear and undoable.
- Manual pre-share review with concealed final previews, inclusion/exclusion, explicit approval and revocation on changes. Native sharing/copy/reviewed Photos saving/Finder reveal use completed files. No automatic sensitive verdict is fabricated or persisted.
- Private cache bypass, workspace concealment (including editing/review sheets), iOS inactive/background handling and text-only recent project lists. Recovery sources/outputs remain; no encrypted vault or secure-erasure claim.
- SHA-256 duplicate skip/import-anyway controls; failed imports can be retried without poisoning duplicate history. Live Photo selections process still images, with explicit still-only messaging.
- Project copies/open/recent/relink, schema-2→3 migration and retained collage state/outputs. Source URL changes invalidate preview keys. Symlink imports become independent validated regular snapshots. Non-file image/project URLs are rejected.
- Mac Automations: versioned recipes/ledger, authorised folder bookmarks, subfolders/new-only/existing options, action toggles/fixed order, shared settings, automatic/manual/privacy-review modes, dashboard/test/retry/duplicate/delete/run/pause, FSEvents hints plus reconciliation, two-second stability checks, hash history/cache, loop rejection, immutable review snapshots and menu-bar monitoring. The main app stays running with Studio closed; quitting stops work and flushes the session. No login item or daemon was installed.
- Original code-generated app icons, privacy manifest, version/build metadata and shared Release bundle identity. Debug retains the earlier mobile identity for development data.

## Architecture and files

Core gained `Adjustments/PhotoAdjustments.swift`, `Annotations/Annotation.swift`, `Privacy/PrivacyMask.swift`, `Privacy/ShareReviewSession.swift`, `Collages/Collage.swift`, `Automations/AutomationModels.swift`, `Import/ContentDigest.swift` and `Export/StagingWriter.swift`. Models, ImageProcessor, crop/source fingerprint and ProjectDocument were extended. Core has no AppKit/UIKit/SwiftUI/Photos imports.

SharedUI gained OverlayEditor, CollageEditor, ShareReview and ProjectsView; library/framing/inspectors changed. Apps/Shared/Workspace owns authoritative edits, source/proposal/profile composition, histories, recovery and cancellation. Mac gained Automations/FolderEvents adapters and app-lifecycle/menu integration. The iOS app gained task navigation, review delivery and concealment integration.

Tests gained ToolboxTests, native AutomationTests and workspace regressions. The project generator/project/schemes now include Mac tests, icon/privacy resources and shared Release identity. `tools/generate_icon.swift` reproduces original assets. AGENTS, README and architecture/specification/roadmap/help/privacy/test/distribution/visual/QA documentation were updated. All changes are within Framepebble.

Coordinate systems: source crop geometry is top-left normalized after orientation/user transforms; masks/annotations are top-left normalized final-output geometry; freehand points are local to their bounding rectangle. Core translates to Core Image coordinates. Changing output aspect/framing can change which content a final-output mask covers: review the final result. Blur/pixelation are not reliable concealment guarantees.

## Build and automated verification

Installed environment: Xcode 27.0, Swift 6.4, iOS 26.5 Simulator. Deployment minimums remain macOS 15/iOS 18. Signing was disabled for these checks.

| Check | Result |
|---|---|
| Shared package on Mac | 55 passed, zero failed/skipped |
| iPhone Simulator shared + workspace tests | 72 passed, zero failed/skipped |
| Native Mac automation tests | 5 passed, zero failed/skipped |
| Mac Debug | Built through app-hosted test scheme |
| Mac Release universal | Built; arm64 + x86_64 |
| iOS/iPadOS Debug Simulator | Built through app-hosted test scheme |
| iOS/iPadOS Release Simulator | Built |

The synthetic 100-image test now renders 80×40 fixtures to actual 1024×1024 JPEG files, checks count/progress/output dimensions/original bytes and completed requests; the recorded Simulator run took approximately 6 seconds. This is not a high-resolution physical-device throughput claim. Shared tests use actual rasters/codecs and run on both platforms. Tests cover real pixel effects, source preservation, staging collisions, local-only URL boundaries, orientation, geometry, native Vision, profiles retaining masks, duplicate retry, project/collage recovery and review approval.

Ignored `.build/toolbox-*.log` and Xcode result bundles hold build/test evidence. Framework `com.apple.linkd.autoShortcut` diagnostics appeared in Mac test logs, but tests passed. No app networking/telemetry code was introduced.

## Native workflow evidence and screenshots

Actual Mac UI: changed exposure with a processed Frame preview; retained existing framing/precision behavior. Created a workflow through native panels for isolated QA folders, enabled it, copied a real CC0 20-megapixel photograph into Input and observed `1 completed · 0 pending · 0 failed`. The 1024×1024 JPEG output validated and input/original SHA-256 remained identical. The workflow was paused and the output retained.

Actual iPhone UI: five-action home, real opaque mask preview, final rendered masked file in review, exclusion revoking share controls, explicit reapproval and successful `Saved 1 reviewed images` to Photos. Live testing caught/fixed a stale boolean-sheet payload bug; item-based presentation now carries completed files. Compact titles corrected an overlapping tool selector.

Screenshots of actual development builds: [Mac adjustments](screenshots/mac-toolbox-adjust.png), [Mac automation](screenshots/mac-toolbox-automation.png), [iPhone home](screenshots/iphone-toolbox-home.png), [iPhone masking](screenshots/iphone-toolbox-mask.png), [iPhone reviewed Photos save](screenshots/iphone-toolbox-review.png). They were captured during implementation; final sidebar/icon/preview refinements could not all be recaptured.

The native UI automation service later failed with `Sky Computer Use native pipe startup failed`, including after reset/reconnection attempts. Consequently the final full collage interaction/export smoke test and final visual refresh were not completed. Eight-image collage rendering/layout/persistence and output recovery are automated-test verified; the complete collage UI workflow still needs manual validation. No fabricated screenshots or UI success claims substitute for that gap. Physical iPhone/iPad/Pencil/trackpad validation was not performed.

## Privacy and distribution

All rendering/indexing/hash/mask/automation work is local. No accounts, cloud backend, uploads, analytics, advertising, telemetry or third-party runtime dependencies were added. Apple-managed Photos/Files/Share may use the user's chosen system/cloud services. Originals remain unchanged; staging is exclusively created and only owned staging files are cleaned up, then validated outputs publish without replacement.

Release targets both use `com.broadframestudio.framepebble`, consistent with Apple's universal-purchase guidance. Signing/team/shared store record/pricing remain unconfigured. Intended one-time target A$29.99 is documentation only. Icons/privacy manifest are prepared, but signed archive/privacy/export-compliance/support/EULA/Store metadata review remains.

SensitiveContentAnalysis was researched against Apple documentation: supported within these deployment targets, signed entitlement and applicable developer/system policy required. No signing team/validated capability/use-case approval is available here. Automatic checking is not implemented or advertised as working; manual review remains usable. SMAppService is the documented future login-item API; no registration was performed.

## Remaining work

1. Complete the blocked collage UI acceptance run, latest screenshot refresh and comprehensive accessibility/Dynamic Type/keyboard/Pencil/trackpad/localization audit. Refine direct resize/rotation handles, multi-line text, collage z-order and magazine typography.
2. Profile real 48-megapixel/100/1,000/10,000-photo collections on physical hardware; establish memory/disk/latency/thermal budgets. Current bounded actors/cache/source-pixel caps are a foundation, not a measured guarantee.
3. Signed sandbox/bookmark/revocation/offline-provider/disk-full/Photos-format/minimum-OS validation. Replaced folders need reauthorisation. Optional launch-at-login remains planned.
4. Storage accounting/removal/orphan cleanup, project portability/relink UX and transactional publication recovery. A crash between publication and ledger update may cause safely numbered duplicate outputs; no guaranteed recovery/secure deletion is claimed.
5. Signed SensitiveContentAnalysis policy/entitlement/legal-use review before any automatic sensitive-check implementation. Foreground-mask framing and arbitrary semantic search remain future work. WebP encoding is unavailable unless ImageIO exposes it.
6. Final brand/icon approval, signing/archive validation, privacy/support text and one shared App Store record. Do not register, publish or submit without approval.

This is a substantial functional development foundation, not a certified production/App Store release.
