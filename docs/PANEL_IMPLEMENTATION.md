# Panel implementation and verification

Follow-up: [second-pass review and corrections](UI_PANEL_RECHECK.md), with expanded small-phone/landscape coverage and newer verification counts. This document records the first implementation pass.

16 October 2026. Implements the approved direction in [the panel review](UI_PANEL_REVIEW.md), against the existing work at `02078d3`. Changes are uncommitted. No processing engine, project schema, Framepebble module/storage path, signing identity or source-ownership model was replaced.

The [implemented screenshot board](UI_PANEL_IMPLEMENTED.html) contains native captures with synthetic sources. The [original comparison board](UI_PANEL_COMPARISON.html) remains the before-review evidence. Neither board establishes a usability score or physical-device performance.

## Result

Mac editing now uses compact icon tools, a 300-point inspector, aligned properties, reversible sidebar collapse and a dedicated Export presentation. The narrow editing window retains a 1040-point minimum when the inspector is open. Export identifies the captured operation, exposes explicit conversion resizing, and keeps progress/cancellation available.

iPhone editing keeps one main photo above the chosen controls. Document switching uses one menu; previous/next, closing and opening photos remain available there. Crop operates on the same photo surface. Large-text editing uses expanded controls rather than compressing the desktop layout. GIF and collage previews have independent property panels rather than sharing one long scrolling page with every setting.

Workspace operation headers name the actual task and count. Changing inputs is explicit; it is unavailable inside the modal Export presentation to avoid starting gallery selection behind a sheet. Existing captured IDs, sparse patches and selection persistence remain intact. Focus has a restrained outline; selection has checkmarks. Show filenames is a display preference, independent of project data.

GIF editing separates Timing, Canvas and Text, active-frame timing from explicit multi-frame selection, and export options from editing controls. Missing-frame badges identify the affected frame. Source recovery has a direct, source-specific presentation listing affected creations, using the existing relink implementation. Export options close before encoding so progress and Cancel remain visible.

Collages distinguish whole-composition, selected-photo and output properties. New creation choices live in the empty state or Actions. Existing art modes remain available; no layouts or tools were added. Saved Collages and Choose Layout are separate destinations. Freeform Move Frames/Reframe Photos modes remain available.

Projects, Sources and Settings are separate sections in the existing management presentation. Mac Automations shows compact workflow summaries and expands the selected workflow's controls, retaining its existing review/publication behavior.

## Review disposition

Numbers refer to the original findings register. “Implemented” describes the code/presentation change, not a claim of validated discoverability for all users.

| Findings | Implementation | Remaining verification |
| --- | --- | --- |
| 01–02 | Removed duplicate choose-input sidebar routes; one explicit operation header and Change Photos action. Convert no longer juxtaposes a captured count with an unrelated zero-selection label. | First-time task discovery study. |
| 03–05 | Removed repeated photo name from regular editor navigation and inspector; compact document menu on phone; consolidated gallery Actions, focused versus selected indicators, workspace vocabulary and singular change labels. | Vocabulary comprehension with new users. |
| 06–07 | Adaptive icon/menu tool picker, Mac sidebar toggle, compact editing navigation and resizable inspector. No text segments clipped into a narrow tool strip. | Multiple display scales and unusual manually resized panel combinations. |
| 08–10 | Dedicated Export presentation; one output plan there; compact Mac property form; aligned crop controls, optional Precision and Crop Help. | Prolonged editing on smaller physical screens. |
| 11–12 | Removed disabled parent tabs/tool strip around overlay drafts; annotation inspector uses shared width; removed sidebar branding/tagline/search repetition. Draft Apply/Cancel and locked navigation preserved. | Annotation rail interaction remains specialized; physical pointer/Pencil and keyboard validation required. |
| 13–14 | Single compact document row, inline tool controls and no duplicated inline photo preview. | Keyboard-open numeric editing and physical touch ergonomics. |
| 15–16 | Persistent GIF preview/transport/frame context and collage canvas with bounded property panels. Creation management moved out of the main canvas stack. | Long sessions, very large compositions and physical memory/performance. |
| 17–19 | Reduced gallery chrome; optional filename row; explicit checkmarks; large-text frame chooser/expanded controls; consolidated task-specific Export. | VoiceOver traversal and first-time discovery. |
| 20–22 | Shared inspector width policy, available-width adaptation, phone-style document controls at narrow widths and actual iPad-shell captures. | Stage Manager and external-display combinations on hardware. Source padding intentionally remains unchanged. |
| 23 | Existing drawing/reframing modes retained with contextual controls and tool state; removed duplicate disabled navigation. | Pencil and pointer ergonomics have not been validated. No claim that different editing gestures have become identical. |
| 24–26 | Direct frame duration, explicit Select Frames, contextual frame menus, scope-labelled creation panels and independently scrolling collage inspector. | Human testing of active-frame versus multi-frame selection. |
| 27–29 | Layout/Saved separation, denser Mac watermark anchors, percentage offsets, Projects/Sources/Settings sections and direct source recovery. | Full assistive-technology traversal. |
| 30–31 | Failed-frame badge and source-specific recovery; compact automation summaries with one selected detail. | Live folder monitoring/publication was not exercised during this UI change. Recovery correctness also covered by existing state tests. |
| 32 | Added state regressions and full-shell capture coverage; inspected captures and running interfaces; superseded historical unsupported score. | Screenshot generation is not an automated clipping/readability oracle. Human usability and physical accessibility gates remain open. |

## Tests and builds

The shared Core suite passed **114 tests, zero failures**. No Core source changed. Native application suites passed **24 Mac tests**, **199 iPhone tests**, and **199 iPad tests with one skipped**, with zero failures. These are per-target counts, not distinct tests to add together. The new three-test `PanelBehaviorTests` suite runs on both platforms and checks captured operation scope, tool/tab changes retaining edits and batch membership, and presentation thresholds/user navigation preference.

The existing app-state, rendering, source-retention, missing-source, preview cancellation, save/reopen, export validation/collision and native adapter regressions ran as part of those suites. New screenshot attachments cover narrow Convert, wide Watermark, the full mobile editing/GIF shell and iPad portrait, landscape and narrow large-text shells. They use generated photos and exercise actual views; captures do not certify usability.

The iPad skip was `testPhotosChangeBlockRunsWithoutMainActorIsolation`: Photos add-only permission had not been granted through its native QA flow. A final iPad compact-layout rerun after the last heading correction also passed (one test, zero failures).

Unsigned **macOS Release** and **generic iOS/iPadOS Release** builds passed. The iOS target supports both phone and tablet. No signing setting changed. Release-tool tests: **2 passed**. Static artifact preflight: **27 passed checks, zero failures, four submission blockers**: public privacy/support URLs need independent verification and both distribution signatures remain unverified. These blockers were deliberately not addressed through signing or publication changes.

Development builds initially encountered restricted SDK/cache access and were rerun with approved build access. Intermediate SwiftUI syntax/type-check failures were corrected before successful checks. The native runs emitted Apple cache `MDB_MAP_FULL` and shortcut-discovery diagnostics; no test failure accompanied those messages. They are recorded rather than represented as proof of either an app defect or a harmless condition on all devices.

## Direct interaction checks

An isolated Debug Mac copy using synthetic review sources was used to choose Convert inputs, enable/disable Also Resize, inspect the actual encoded preview, choose a temporary export directory and publish one JPEG. The preview reported **320 × 160 pixels, 1,707 bytes**; the published file was **1,707 bytes**, and the app reported **1 exported · 0 failed**. Source-dimension mode and the captured one-photo operation remained intact after returning. Existing safe publication was reused.

The running iPhone Simulator was used to open a synthetic photo, switch Adjust to Crop and inspect the actual canvas and lower controls. The image stayed in the same editing surface and crop controls remained reachable by scrolling the lower panel. iPad and large-text evidence was inspected from native hosted full-shell captures; this is not a claim that every iPad gesture was manually exercised.

## Evidence locations and reproduction

Full logs and `.xcresult` bundles are local, outside version control:

- Core: `/tmp/ameluma-panel-core-tests.log`.
- Mac: `/tmp/ameluma-panels-final-mac.log`; derived data `/tmp/ameluma-panel-mac`.
- iPhone: `/tmp/ameluma-panels-final-phone.log`; derived data `/tmp/ameluma-panel-ios`.
- iPad: `/tmp/ameluma-panels-verified-ipad.log`; derived data `/tmp/ameluma-panel-ipad`.
- Final iPad layout: `/tmp/ameluma-panels-final-ipad-layout.log`.
- Release: `/tmp/ameluma-panel-release-mac.log`, `/tmp/ameluma-panel-release-ios.log`.
- Tools/preflight: `/tmp/ameluma-panel-release-tools.log`, `/tmp/ameluma-panel-preflight.log`.

Use `swift test` in `FramepebbleCore`, and `xcodebuild test` with schemes `FramepebbleMacTests` and `FramepebbleCoreiOSTests` for the native suites. Build `FramepebbleMac` and `FramepebbleiOS` in Release with `CODE_SIGNING_ALLOWED=NO` for unsigned compilation. Run `python3 -m unittest discover -s tools/tests` and `python3 tools/review_release.py --mac-app <artifact> --ios-app <artifact>` for tooling/preflight.

The boards intentionally retain named captures from completed runs. The phone board includes the final inline heading correction. Help now documents the actual panel navigation. Historical counts and old captures are not presented as evidence for these changes.

## Remaining acceptance work

The code changes implement the proposed panel direction; the audit's final human-validation stage is still open. Physical iPhone/iPad testing must cover keyboard-open entry, VoiceOver, Voice Control, Switch Control, Pencil, pointer, multitasking, orientation changes, external displays, large photo collections, export interruption and sustained performance. Representative new users should perform photo-first and action-first tasks without coaching. Do not describe the result as fully accessibility-certified, physically performance-validated or equivalent in usability to a competitor based only on these tests.

Processing remains local. Local project instructions are not self-contained cross-device projects. Sensitive-content checking still depends on system capability/signing; GIF review remains manual; GIF presets primarily change dimensions. Explicit Mac browser-image imports may download the requested image. Those documented limitations remain unchanged.
