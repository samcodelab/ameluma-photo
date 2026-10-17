# UI panel recheck — second pass

16 October 2026. Reviewed the uncommitted implementation following `02078d3`, preserving all previous work. This is a follow-up to [the original review](UI_PANEL_REVIEW.md) and [first implementation report](PANEL_IMPLEMENTATION.md). No commit, push, signing change or publication was performed.

The first pass improved the usual portrait and desktop layouts, but it did **not** establish dependable behavior at every size. Fresh small-phone and landscape captures found real failures. A second correction was also necessary: merely hiding the lower panel made the landscape photo visible but too small. The visibility regression continued to fail until navigation moved into the native bar and the tools moved to a side rail. The test threshold was not lowered to make that pass.

See the [second-pass before/after board](UI_PANEL_RECHECK.html). Screenshots use generated photos, not user images. Hosted viewport captures and actual Simulator rotation are distinguished below.

## Confirmed findings and changes

| ID | Priority | Finding in the first implementation | Second-pass result |
| --- | --- | --- | --- |
| R01 | P1 | Landscape Editor could lose the photo behind a fixed lower panel. Removing that panel alone still left a very small photo surrounded by navigation. | Native navigation-bar document controls, a side tool rail and an overlaid pixel-inspection control recover vertical space. Small-phone and landscape photo visibility assertions now run. |
| R02 | P1 | The 230-point panel was too costly on a 320 × 568 phone. | Short viewports use expanded tool controls. Ordinary portrait uses a bounded lower panel; the photo remains visible. Crop has an expanded control presentation using the same editing state. |
| R03 | P1 | Landscape GIF transport, frame strip and properties exceeded the available height. | Short viewports combine transport, frame chooser and Tools. Long properties open separately. Large-text layouts retain their readable alternative. |
| R04 | P1 | Collage imposed a 500-point minimum height on iOS, clipping a landscape canvas. Several supporting sheets also carried desktop minimum heights. | Desktop height constraints remain on Mac; mobile presentations use their available height. Landscape collage documents move into Actions, leaving the canvas and independently scrolling inspector. |
| R05 | P1 | Some shared tool buttons used 30 × 28 desktop geometry on iPad; hiding phone tool captions exposed generic symbol accessibility names such as “Hide.” | Shared mobile inspector buttons have 44-point regions; photo and annotation tools retain touch targets. Icon-only phone tools explicitly announce Adjust, Crop and Privacy; the overflow announces More photo tools. |
| R06 | P1 | Opening a shorter saved GIF could retain an out-of-range frame index and unrelated frame/annotation selection. Undo/removal could also leave stale selection IDs. | Focus reconciles project identity, clamps the index and removes invalid frame selections. Opening a different project clears transient annotation and multiframe focus without changing saved frame settings. Two regression tests cover these transitions. |
| R07 | P2 | A manually widened Mac inspector could squeeze the canvas despite the new default width. | At 1040 points with navigation visible, the requested inspector width is bounded to preserve the 460-point canvas budget. Wider windows can still use a 420-point inspector. Dragging starts from the displayed width. |
| R08 | P1 | Collage’s header Export immediately rendered and shared, before users could review the newly separated output options. | Export opens an output presentation with actual photo count, dimensions, format and quality. Export & Share captures the same existing inputs and uses the existing safe renderer/publication path. Cancelling options creates no output. |
| R09 | P2 | An existing collage with no cells could leave a blank preview or indefinite rendering presentation. | Empty compositions now explain the next step and offer Select Photos. A capture covers removing all cells and restoring the composition. |
| R10 | P2 | GIF error/replacement controls were laid out inside the output aspect ratio and clipped, especially with tall canvases, short windows or large text. | Recovery uses the full preview region with scrolling, while successful preview and annotation geometry remain tied to the output canvas. |
| R11 | P2 | Grouped form chrome still dominated the phone’s short Adjust panel. | Inline Adjust reuses the same field-specific bindings in a compact scrolling property stack. Quick Fix, numeric values, sliders, reset and history behavior remain intact. |
| R12 | P2 | Long Choose Layout/Saved Collages segments were unsuitable at accessibility text sizes. | The large-text destination switch uses a labelled native menu. Other sizes retain segments. |
| R13 | P1 | Adapting panels directly to a keyboard-reduced height could remove the focused field and dismiss typing. | The editor, GIF and collage retain their chosen viewport presentation while height alone changes. Width/orientation changes establish a new presentation. A regression test covers typing-height changes and rotation. Software-keyboard hardware verification remains open. |

An integration issue encountered while adding GIF focus tracking was corrected before final validation: the empty editor must retain one stable fallback project identity rather than construct a new UUID on every read. The first targeted run was stopped after this caused repeated view refreshes. This is recorded as an issue encountered during the work, not evidence that the old application always exhibited that loop.

## Comparison with established interfaces

The same reference criteria were applied again: one main image surface, properties attached to the active task, compact navigation, explicit action scope, accessible icon names and touch-appropriate targets. [Apple Photos’ editing flow](https://support.apple.com/guide/iphone/edit-photos-and-videos-iphb08064d57/ios) and [Pixelmator Pro’s adjustment grouping](https://support.apple.com/en-euro/guide/pixelmator-pro-ipad/pix1e05b7354/ipados) remain relevant references. [Apple’s toolbar guidance](https://developer.apple.com/design/human-interface-guidelines/toolbars) supports prioritising common commands and handling secondary actions deliberately; [its button guidance](https://developer.apple.com/design/human-interface-guidelines/buttons) informs platform control sizing and presentation.

These are design criteria and comparisons, not evidence that Ameluma has matched those products’ usability. No proprietary tools, assets, layers, cloud model or editing engine were copied. Natural aspect-fit margins are not counted as avoidable wasted space. In particular, a portrait GIF on a landscape screen must retain its chosen output aspect ratio.

## Direct interaction evidence

- **Mac saved GIF:** selected frame 5 of a five-frame synthetic GIF, opened a one-frame saved GIF through More → Saved GIFs, and observed Frame 1 of 1 with its duration control. No workspace restoration was needed.
- **Mac collage:** entered Photos selection, selected one synthetic source, returned to the composition, and opened Export. The sheet exposed output format and Export & Share before any export began. This verifies the options/navigation change; it does not claim a new end-to-end collage publication check in this pass.
- **iPhone:** opened a synthetic photo, entered exposure `0.4`, and observed the numeric value and slider update together. Rotating the actual Simulator produced the side tool rail and document controls in the navigation bar. The on-screen software keyboard was not displayed by this Device Hub configuration, so keyboard geometry is covered by the presentation-state regression rather than claimed as manually verified.
- **iPad:** native full-shell captures cover landscape, portrait and a narrow large-text window, alongside state and adapter tests. Physical touch, Pencil and pointer ergonomics remain unverified.

## Verification

Final checks passed:

| Check | Outcome |
| --- | --- |
| Shared Core | 114 tests, zero failures |
| Mac native suite | 27 tests, zero failures |
| iPhone native suite | 202 tests, zero failures |
| iPad native suite | 202 tests, one skipped, zero failures |
| Unsigned Mac Release | Build succeeded |
| Unsigned generic iOS/iPadOS Release | Build succeeded |
| Release-tool tests | 2 passed |
| Static artifact preflight | 27 passed checks, zero failures, four distribution blockers |
| Whitespace check | `git diff --check` passed |

These are per-target suite totals, not distinct tests to add together. The iPad skip is the Photos change-block integration test, which requires add-only permission through the native QA flow. The four preflight blockers are independently verified public privacy/support URLs and verified distribution signatures for each platform. No signing change was made to remove those blockers. Shared processing source and project schemas remain unchanged.

Local logs: `/tmp/ameluma-recheck-core.log`, `/tmp/ameluma-recheck-final2-mac.log`, `/tmp/ameluma-recheck-final2-phone.log`, `/tmp/ameluma-recheck-final2-ipad.log`, `/tmp/ameluma-recheck-release-mac.log`, `/tmp/ameluma-recheck-release-ios.log`, `/tmp/ameluma-recheck-tools.log`, `/tmp/ameluma-recheck-preflight.log`. Native `.xcresult` bundles are under the existing `/tmp/ameluma-panel-{mac,ios,ipad}/Logs/Test` directories. The self-contained board embeds selected final captures so those temporary paths are not needed to view its evidence.

The added regression tests protect saved-GIF focus, removed-frame selection and keyboard presentation. Existing operation-scope, sparse-edit, source retention, preview recovery, cancellation, save/reopen, collision and native-adapter tests remain in the platform suites. New captures cover small-phone Editor, landscape Editor/GIF/collage, and empty collage. The photo-visibility assertion rejects a collapsed image but is not a usability score or a general clipping detector.

Intermediate full runs had one visual assertion failure each. Diagnostic collection then lingered after the test host exited; those completed failing commands were interrupted before rerunning the corrected layout. Later runs use `-collect-test-diagnostics never`, which disables verbose diagnostic collection, not assertions. Apple cache/accessibility-loader diagnostics also appeared. Passing results are reported separately from these intermediate failures.

## Remaining action plan

1. **Physical devices:** exercise software-keyboard entry and dismissal, rotation while typing, Stage Manager and height-only window resizing. Width-driven presentation intentionally avoids destroying a focused form during keyboard height changes; freeform window behavior needs hardware assessment.
2. **Accessibility:** run VoiceOver, Voice Control, Switch Control, keyboard-only and maximum Dynamic Type task walkthroughs. Explicit labels and larger regions are improvements, not a complete accessibility certification.
3. **Usability:** ask first-time users to convert, censor, adjust, create a GIF and export a collage without coaching. Record misidentified icons, backtracking and misunderstood scope before making more structural changes.
4. **Stress and distribution:** validate sustained large-source performance, interruption and memory pressure on phones/tablets. Public support/privacy URLs and distribution signatures remain separate release work requiring authorization.

No remaining claim of “finished UI” or numerical usability rating is justified by this review. The confirmed panel defects above were addressed; those real-device and human-validation gates remain open.
