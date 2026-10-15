# Ameluma Photo product specification

Framepebble, by Broad Frame Studio. **Your photos. Your way.** Native local photo tools for macOS 15+, iOS/iPadOS 18+. Intended commercial model: a one-time universal purchase, target A$29.99. No price, store listing, subscription or account has been created.

## Studio — implemented

Native multiple-file/folder/Photos imports, thumbnails and a lazy library; favourites, edited and review filters; Vision label search with actual observations. Browse, Frame and Compare share one editing state. Drag/pinch/Option-scroll framing, precision position/zoom/aspect/rotation controls, Smart/Keep Subjects and manual overrides remain intact.

Fit, Fill, Stretch, Preserve Aspect Ratio and Canvas; explicit dimensions/resize bases; backgrounds/alignment/padding/no-upscaling; rotation/flips/straightening. Seven bounded photo adjustments and conservative Quick Fix. Contextual Frame/Adjust/Create/Export inspector groups keep unrelated settings out of the current task. iPhone opens with Batch Edit, Editor and Collages workflows and recent workspace/project access; iPad adapts the larger workspace. A selected photograph can be rotated directly from the phone collection.

Classic Grid, Magazine and Freeform collages retain editable source references/cell geometry/framing. Add/remove/swap sources, drag/zoom within cells, adjust freeform positions/rotation, spacing, dimensions, backgrounds, borders/corners/shadows, titles and captions. Layout changes retain existing crop intent where possible; collage Undo/Redo and project persistence are implemented. The visual gallery offers 74 algorithmic layouts. Multiple named collage tabs, whole-composition and individual-cell shapes, photo-filled CoreText lettering and approximate reference-colour/tone photomosaics are implemented; up to 10,000 cells are supported. See COLLAGES.md for limits.

Editable text/arrows/lines/rectangles/ellipses/freehand overlays use normalized output geometry. Text offers fonts, bold font choice, alignment and colour. Selected areas can be dragged; handles provide direct size/rotation editing and numeric fields provide precision alternatives. Hide Something provides rectangular/elliptical/freehand opaque covers, blur, pixelation and frosted effects. Crop to Hide opens precision reframing for manual exclusion. No automatic intimate-region detector exists.

Text/image/tiled watermarks, native-capability-gated output formats, quality/target-size controls, colour/metadata policies, saved profiles and multi-profile output remain implemented. Outputs are staged, decoded/validated and published exclusively; originals are never overwritten. Cancellation retains completed outputs and pending retries.

Native sharing uses final processed outputs. Manual review starts with concealed previews, supports exclusions and explicit approval, and revokes approval when inclusion changes. Share/copy/reviewed Photos saving and Mac Finder reveal are available after approval. Ordinary Files export and Photos saving remain available; optional review can precede Photos delivery. Automated sensitivity analysis is unavailable in this unsigned build; no result is fabricated and no image is certified safe.

Projects autosave locally, migrate schemas 2/3 to 4, save/open instruction files and expose recent local project copies. Missing sources can be relinked to new unchanged snapshots while retaining UUIDs/edits. Project instructions contain references/editable state, not embedded originals; transferring them can require relinking. Private Editing Mode disables the memory thumbnail cache and allows concealment; sources/projects/outputs remain for recovery. Duplicate imports can be skipped by streaming SHA-256 or imported anyway. Live Photos use the still component and export ordinary still images.

## Automations — implemented on Mac

Multiple Input → Actions → Output recipes use Studio's configuration/engine. Folder panels persist security-scoped bookmarks. Subfolder/new-only/existing-file options, enable/pause, action toggles, fixed pipeline order, native formats/naming, automatic/manual review/privacy review modes are available. Dashboard supports create/edit/duplicate/delete/run/test/pending approval/failed retry and counts.

FSEvents plus reconciliation scans, repeated fingerprint stability checks, image validation, snapshot verification and hash history prevent common incomplete-transfer/duplicate-event problems. Input/output ancestry and cross-workflow loops are rejected. Tests render a sample without writing the destination. Review queues show processed previews and withhold publication. Menu-bar controls keep monitoring available with Studio closed; quitting stops it. No login registration or daemon has been installed.

## Limits and remaining work

This is a development implementation, not a production release. Required work includes physical-device performance and 1,000–10,000-photo QA, signed sandbox/bookmark/provider tests, VoiceOver/Dynamic Type/localization/Pencil/keyboard audits, refined annotation handles and multi-line typography, arbitrary collage stacking controls, storage cleanup/accounting, transactional crash recovery and project portability UX.

Vision can fail or be incorrect. Foreground-mask framing and arbitrary semantic search are not implemented. WebP output is exposed only if a native encoder exists. SensitiveContentAnalysis needs a signed capability and applicable developer agreement/policy; eligibility and this sharing use case require distribution review. Blur/pixelation, metadata restrictions and manual review do not guarantee anonymity or concealment. Folders replaced/offline/revoked may require reauthorisation. Publication-to-ledger crashes can produce safe numbered duplicates. Launch at login is planned, not displayed as a working feature.

Release targets share a bundle ID for universal purchase. Signing/team/record setup, final icon/brand approval, store metadata, EULA/privacy/support review and archive/device validation remain. Marketing must reflect these limitations; “completely private” must not imply control over user-selected system cloud/sharing destinations.

The four-workflow navigation and eight review fixes are detailed in WORKFLOWS_AND_EDIT_SAFETY.md. Export actions explicitly identify their operation, profile plans show actual file counts, and encoded previews demonstrate lossy output. Automatic classification remains separate from Edited badges.


## Library and tabbed Editor

The Photo Library is the gallery. Batch Edit, Editor, Collages and Mac Automations are separate workspaces sharing its sources and editing state. Privacy Review is a library filter; Privacy is an Editor tool, available from the editor toolbar or a photo’s context menu.

Mac and iPad Editor show explicit, closable photo tabs. iPhone uses an Open Photos menu. Tabs are unique per source and independent of gallery focus, filters and batch membership. Export/share targets only the active editor photo. Closing a tab preserves all project edits and original files; closing the last returns to the gallery. Optional tab IDs and the active tab are saved in schema-4 projects, with absent fields defaulting to an empty session in older projects. Per-tab tool context is retained during the current app session and starts at Adjust after reopening a project. Apply or cancel an overlay draft before switching tabs or workspaces.


Product branding: **Ameluma Photo**; iPhone/iPad icon display name: **Ameluma**. Legacy internal module/target names and storage paths remain for compatibility.
