# Workflow review implementation

This pass addresses the concrete safety/usability findings from the comparative review. It preserves originals, existing effective image edits and the local processing architecture. It does not claim every suggested future enhancement or release-validation activity is complete.

## Completed changes

| Review area | Implementation |
| --- | --- |
| Stale collage output | CollageRenderIdentity includes the composition and only relevant sources/effective settings. Current Export sharing requires a matching identity; previous files remain in export history. |
| Stale collage preview | Pending/failure states are visible over the previous preview; failed initial renders show a real error. |
| Async Quick Fix | Captured results merge only unchanged fields into current edits. Newer manual values survive; missing/relinked sources are skipped. Results commit as one named Undo step. Progress and cancellation are available; cancellation applies none of the staged automatic results. |
| Detail inspection | Full-resolution photo/output and composition inspection with Fit, display-scale-aware 100%, zoom and scrolling. Encoded proof retains the actual encoder, dimensions/bytes, profile selection and batch sample navigation. Normal previews stay downsampled. |
| Crop constraints | Ratio lock, Keep Export Dimensions, live dimension feedback, Done Cropping, and an Edited Output preview inside the crop tool. Drag geometry remains shared. |
| Privacy coverage | Masked photos are flagged after spatial changes. Review state is separate from Vision/framing and persisted in schema-4 optional fields. Collage geometry edits have an independent coverage-review flag. Confirmation is manual, not a concealment guarantee. |
| Direct watermark | Separate Watermark/Export tools; single watermark movement, corner scaling and rotation reuse Core bounds/rendering. Tiled patterns retain inspector controls. |
| Tool discovery | Focused inspector identifies its current tool; iPhone has stable bottom Adjust/Crop/Privacy plus Tools. Accessibility-size Tools/View menus preserve photo space. Mac M-key original comparison supplements the Original toggle. |
| Undo | Quick Fix is grouped; photo operations and the Mac Undo/Redo menu identify their target/operation. Existing session history and per-collage histories remain. |
| Photo tabs | Thumbnail identity, lazy strip, drag ordering, Close Others and searchable open-document chooser. Closing preserves saved edits. |
| Collage tabs | Drag ordering, Close Others and distinct open versus saved compositions. Each composition retains independent edits/history. |
| Project identity | Optional project name is saved/restored and appears above the library. Projects no longer has a destructive-sounding navigation label. Clear is in Local Source Storage. Saved rows load actual project names. |
| Fixed batches | Optional saved input IDs remain stable while filtering/navigation changes. Target photos receive Batch Input indicators. Live selection remains an explicit alternative. |
| Exceptions/mixed values | Individual Overrides filter identifies actual per-photo exceptions. Width/height/fit/format explicitly label Mixed; adjustment indicators remain. |
| Profile output clarity | Current Edits Only deselects profiles without deleting them. Resolved filename examples reuse the export filename implementation; numeric collision suffixes remain safe. |
| Collage editing | Separate Move Frames/Reframe Photos; direct shared move/resize/rotation, optional canvas snapping, layer ordering, thumbnail replacement and drag-to-swap. Slider gestures are grouped in Undo. Numeric alternatives remain. |
| Collage discovery | Recommended/category/orientation filtering and actual-photo previews. Templates preview up to 24 photos; saved compositions preview their actual content. Private Editing Mode uses diagrams. |
| Mosaic guidance | Reference, tile candidates and detail steps; candidate counts and valid-generation gating. Reference matching remains approximate. |
| Automation navigation | Workflows, Pending Reviews and Failed Jobs views; explicit input/output/publication mode. Tests still do not publish, and required approval remains explicit. |
| Storage/privacy preferences | Read-only owned-source accounting: file count, retained/unreferenced file sizes. Clear protections unchanged. Project UI exposes Private Editing and duplicate-import controls with storage/system limitations. |

## Compatibility and safety

Schema 4 adds optional project name, fixed batch IDs, privacy review IDs and a collage review boolean, defaulting safely for older documents. No source bytes or existing processing definitions are rewritten by migration. The renderer, geometry, watermark bounds and filename resolution stay in FramepebbleCore; SwiftUI gesture/display adapters are shared by the apps. No networking, analytics, cloud models or third-party dependencies were added. No commit or push is included in this pass.

## Partial and remaining items

| Item | Status / reason |
| --- | --- |
| One identical editor shell for every tool | Improved shared document context, contextual inspector and mobile tool strip. Privacy/annotation still intentionally use a reversible draft sub-editor. The normal editor and wide draft editor share the tool strip and document context; draft Apply/Cancel remains intentional. |
| Mixed state in every widget | Critical dimensions/mode/format and adjustments are labelled. Every toggle/colour/picker has not been converted to an indeterminate widget. |
| Text art typography | Selected outline fonts and multiline text are implemented. Older projects retain legacy single-line geometry until regenerated. Colour emoji/arbitrary bitmap masks remain unsupported. |
| Collage output | Native capability-checked formats, quality, encoded proof and reviewed destination copies are implemented. The output review step remains explicit. |
| Detachable windows | Tab ordering/closing/search improved; detachable document windows are not implemented. |
| Persistent Undo/checkpoints | Saved edits remain; histories are session-scoped (80 steps), not a permanent edit archive. |
| Sharing steps | Deliberate approval/exclusion remains. No review gate was removed merely to save a click. |
| Physical devices/VoiceOver/Pencil | Native generated-image captures and model tests are evidence, not physical-device or complete accessibility validation. |
| Real NAS/50,000-photo/10,000-tile performance | No representative external NAS corpus or physical-device benchmark was run. Existing synthetic large-library and thousand-tile regressions remain; no throughput/quality-parity claim. |
| Sensitive Content Analysis | Still gated by actual signing capability and system policy. No entitlement registration or real detection validation was performed; manual review remains available. |
| Public policy/support URLs | Still awaiting owner-provided URLs; none fabricated or published. |
| Full comparative usability study | Official competitor patterns informed the changes; no measured head-to-head user study is claimed. |

Full-resolution inspection can consume substantial memory for high-resolution sources/compositions. Test representative hardware before release. Mask coverage confirmation is not automated detection; review the final output for each profile and composition.

## Validation for this pass

104 Core tests, 174 iOS Simulator app-host tests (including Core) and 21 native Mac tests passed. Both application targets build unsigned. Generated-image native captures cover Mac and compact/adaptive layouts; they do not establish physical-device, NAS-scale or complete assistive-technology validation.
