# Architecture

## Target boundaries

Separate native SwiftUI macOS and iOS/iPadOS targets link one local FramepebbleCore package. Core imports Foundation, CoreGraphics, CoreImage, ImageIO, CoreText, Vision, CoreML, UniformTypeIdentifiers CryptoKit for streaming hashes and Darwin's exclusive rename API. It imports no AppKit, UIKit, SwiftUI or Photos frameworks. The MainActor Workspace coordinator and shared SwiftUI views are compiled into both apps. Native panels, modifier-scroll capture, Photos/Files integration and finite background-save handling stay in platform adapters.

## Models and shared state

SourceAsset references a local snapshot by URL/UUID/name. ProcessingConfiguration describes output geometry, colour, encoding, metadata and watermarking. CropConfiguration stores normalized position, zoom, quarter turns, flips, straightening and framing mode. ImageOverride stores per-image framing, aspect-only dimension overrides that follow batch width, and optional explicitly scoped processing settings independently of batch defaults. EditingSnapshot is authoritative for both grid and precision views; EditingHistory keeps up to 80 undo states. Continuous drag and slider gestures are grouped into one history transaction.

FramingProposal is analysis provenance plus review reasons, not another editable crop state. All surfaces and exports read EditingSnapshot. Changing batch dimensions preserves override geometry and flags affected images. Orientation changes preserve state and require review rather than silently discarding adjustments. Quarter-turn precision controls rotate normalized intent using shared geometry. Undo/Redo flags changed framing conservatively for review. Quality changes never discard manual crops.

## Coordinate and render pipeline

Crop coordinates use a top-left origin on the EXIF-oriented, user-transformed source, normalized to its dimensions. CoreImage's bottom-left coordinates are converted within the renderer. CropGeometry computes the largest inscribed output-aspect rectangle, divides it by zoom and clamps its centre. Drag translation is converted from displayed-frame units through this visible rectangle into normalized source units. Mouse and touch therefore use the same algorithm. FramingLayout supplies the exact source-to-output affine layout to raster rendering, raw gesture presentation and subject guides, including Fit/Canvas placement and upscaling prevention.

The frame stays fixed while a downsampled source moves inside it. SwiftUI uses the shared crop rectangle for immediate gesture presentation. During unmasked framing gestures, the view displays the source and guides; the fully composited preview returns after the gesture. Masked configurations keep processed previews and refresh at reduced resolution, so gestures do not reveal an unmasked source. No full-resolution render is launched during dragging. Gesture completion and ordinary controls use the same Core rendering configuration as export. Small downsampling/font-rasterization differences can occur in previews.

The pipeline validates content → decodes/downsamples → applies EXIF orientation once → applies user rotation/flips/straightening → applies bounded photo adjustments → computes resize/framing/canvas geometry → composes background → applies privacy masks → renders annotations/borders/corners → adds watermark → converts colour → encodes → reopens/decodes staging → publishes. Crop-before-scale is an equivalent affine implementation of resize/framing. Final export always starts from the snapshot, never a prior compressed output. Percentage/longest-edge sizing uses original nominal dimensions even in reduced previews.

Fit preserves the whole image inside exact requested dimensions. Fill/Manual use the output frame's ratio, preserving source proportions. Stretch intentionally distorts. Canvas adds alignment/background choices. Preserve Aspect Ratio derives dimensions from width, height, longest edge or percentage. Prevent Upscaling caps content scaling and pads the requested canvas when necessary. Straightening uses the transformed source bounding box and may expose background corners; review the result.

## Analysis and search

VisionAnalyzer is a separate serial actor. It uses VNClassifyImageRequest for actual labels/scores and request revision. ClassificationIndex stores labels, revision and fresh file-size/modification fingerprints. Foundation URL resource caches are cleared before fingerprint reads. Workspace asynchronously prioritizes the selected item and visible thumbnails, then remaining sources; stale fingerprints/revisions invalidate records. Rendering and import are not blocked by the Vision actor, although source thumbnail generation shares the bounded rendering actor.

Search matches case-insensitive tokens against actual labels above a 0.15 threshold, requires every token and ranks by the lowest matching confidence. Suggestions use labels above 0.3. These are policy thresholds, not calibrated accuracy percentages. Multiword matching is label intersection, not natural-language understanding. Missing records never yield fabricated results. No downloaded or third-party model is used.

Framing uses face, human and animal rectangles, then attention/object saliency when no subject rectangles are available. Nested detections are deduplicated; larger spatial regions are preferred. Smart targets one region; Keep Subjects targets their union. Classifications never stand in for spatial detections. Failure/no regions produces a deterministic centred fallback. Regions outside the computed crop, ambiguity/multiple regions and insufficient source resolution produce review reasons. A successful request does not guarantee correctness. Foreground instance masks remain an investigation item. Simulator requests explicitly select supported CPU compute devices because default Espresso setup failed on the installed runtime; physical devices use Vision's default device selection.

## Watermark and output

CoreText builds text stamps. ImageIO downsamples logo inputs. WatermarkRenderer uses output-relative width, opacity, margins/offsets, nine anchors, rotation and bounded tiling. It composites after framing/canvas. The same renderer serves previews and exports. ImageContentAnalyzing and SpatialFramingAnalyzing keep label indexing separate from spatial framing and allow future local analyzers. Native ImageIO capability lists determine exposed codecs. JPEG/PNG/HEIC/TIFF roundtrips are tested on the installed systems; WebP output remains hidden when no native encoder registers it.

Target-size encoding first tries selected quality, then minimum quality, then at most seven bounded binary-search attempts. Infeasible targets throw without publishing an output. Profiles snapshot dimensions, framing, format, quality, watermark, metadata and naming settings. Multiple chosen profiles share source URLs and produce separate output folders. Per-image crop overrides continue to apply. Dedicated destination/bookmark management is not implemented.

## Files, persistence and cancellation

Import holds a security scope only while making an unchanged local snapshot. Recursive folder enumeration skips symlinks, hidden files and packages. Session data stores references to these snapshots, not embedded images. The snapshots are disk copies in local Application Support. Projects are schema version 4, with version-2/3 migration; additive processing/crop fields decode with defaults, and unsupported project versions fail visibly. The current UI restores an autosaved session and can save/open project copies and relink a selected source. Recent projects list names without image thumbnails. Private snapshot, logo and local output references are rebased when an iOS update relocates the app data container; missing sources invalidate stale classification records.

Export requests persist their source, settings, profile and stable request ID. Each success removes its exact pending request; retries process only remaining requests. Results retain stable IDs so a successful retry replaces its prior error without hiding earlier completed outputs. Autosaves are debounced; iOS cancels image/analysis work on backgrounding and requests a short system background allowance to flush local state. This is not indefinite background processing. A power loss between output publication and ledger persistence may leave a valid unrecorded output; numbered collision handling still protects it, but exact crash deduplication is not guaranteed.

A staging file is written exclusively in the destination directory. ImageIO validates content status, type and decoded dimensions. `renamex_np(RENAME_EXCL)` publishes without replacing any existing file, symlink, directory or source alias. Collision names are numbered. Staging cleanup runs on failure/cancellation. File-provider refusal of exclusive rename is reported, without an unsafe overwrite fallback. Exporting resumes with a freshly selected destination after relaunch; external security scopes are not assumed durable.

## Performance boundaries

One full-resolution rendering job and one Vision analysis run at a time. Thumbnail NSCache budgets are 32 MB and 128 entries. Lazy views discard retained images when disappearing. Grid sources/previews follow tile size; precision surfaces use larger downsampled sources. Full-resolution exports can still require multiple large buffers. Source storage, real-device peak memory, thousands-item indexing latency and extreme-aspect preview presentation need measured release validation before claims about arbitrary large batches.

## Foreground-mask investigation

The installed Apple SDK declares VNGenerateForegroundInstanceMaskRequest and revision 1 as available on macOS 14/iOS 17, within these deployment targets. Its VNInstanceMaskObservation provides instance masks rather than direct classification labels. Integrating mask-derived bounds would add pixel-buffer analysis and memory/latency costs. The present implementation uses spatial rectangles plus attention/object saliency; mask integration awaits a measured subject corpus and remains clearly unimplemented in the UI.

## Mac layout compatibility

The Mac workspace uses a bounded SwiftUI HStack with a native List sidebar and a draggable 310–470-point inspector divider. Native inspector/split-controller sizing produced a constraint-loop abort on the installed macOS runtime during QA. The bounded layout avoids those controllers while retaining native controls, collapse, resize and shared editing state. Startup, refinement and divider resizing are checked on the actual app.

Source decoding has a configurable pixel budget (100 million pixels by default), checked before full decoding or snapshot copying. Text-stamp allocations are capped at 16 million pixels. These reject extreme inputs/marks clearly; they do not substitute for physical-device peak-memory validation.

Photos change blocks are created inside a nonisolated platform adapter as explicitly Sendable closures. Photos executes them on its own queue; UI state and completion summaries remain on MainActor. PHAssetCreationRequest resource creation surfaces unsupported-format failures through the framework commit rather than silently treating a nil request as success.

## Everyday edits, overlays and collages

PhotoAdjustments uses native Core Image filters, explicit neutral values and validated slider bounds. Quick Fix samples a downsampled image: conservative average-luminance exposure and red/blue warmth heuristics combine with supported native auto-adjustment suggestions. Grey-world colour assumptions can be wrong for deliberately coloured scenes. Straighten applies a native suggestion only when one exists; it can legitimately propose no change. Users can reset or undo every result.

Annotations and masks use top-left normalized final-output geometry; their coordinates are distinct from source crop coordinates. Freehand points are normalized inside their own bounding rectangle, so moving/resizing the rectangle moves/resizes the path. Rotation is clockwise. Core Graphics renders vector overlays; text/captions reuse CoreText watermark stamps. Privacy effects use output-resolution Core Image filters and Core Graphics mask rasters. Opaque covers have full alpha. Masked exports omit copied supported source metadata dictionaries even when preservation was selected. They encode one flattened raster without the original, project JSON or editable masks. ImageIO may add new descriptive metadata. Blur/pixelation are not guaranteed concealment.

CollageProject stores source UUIDs, normalized cell rectangles/crops, layout, title, captions and canvas styling. Cells render original snapshots sequentially through ImageProcessor, not through another transformation engine. Layout changes preserve existing cell crop IDs/intent where possible. Core Graphics composes the cell rasters; shared annotation rendering adds captions. Workspace maintains a bounded collage history and includes collage state in schema 4. Cell controls provide numeric/slider alternatives to dragging. A saved project retains references; moving it to another device may require relinking photographs.

## Sharing and private editing

ShareReviewSession is ephemeral and non-Codable. Approval belongs to a particular set of completed outputs; changing inclusion revokes it. Previews begin concealed, and external share/copy/Photos controls appear after explicit approval. Ordinary Files export remains available without optional review. Apple SensitiveContentAnalysis is not called or entitled in this unsigned build. No sensitive verdict is fabricated or stored. Private Editing Mode bypasses the memory thumbnail cache; no persistent thumbnail cache exists. Concealment covers the workspace, including on iOS backgrounding. Saved projects/sources/exports remain for recovery, and system screenshots/backups/cloud-managed directories remain outside app control.

## Mac Automations

The macOS adapter persists version-1 AutomationLedger recipes, bookmark data, hash history, pending review snapshots and failures. Configuration is the same ProcessingConfiguration used by Studio. Action toggles neutralize disabled operations; the processing order is fixed to avoid undefined sequences. Orientation normalization is always part of decoding. Native encoder absence is an error when conversion is disabled.

FSEvents are hints; a serial worker also performs periodic reconciliation. Two identical size/modification observations and successful image validation are required before snapshotting. Source and snapshot hashes/fingerprints are checked around the copy. Streaming SHA-256 is bounded to 1 MiB chunks; unchanged fingerprint/hash caching avoids repeated full reads. Hash history and pending/failed queues prevent duplicate events from repeating work. Input/output ancestry, aliases and cross-workflow folder overlaps are rejected. Processing never changes the input.

Automatic outputs use the normal staging/validation/exclusive publication path. Review and privacy-review workflows hold immutable source snapshots before publication; the user previews processed pixels and explicitly approves. No automated sensitivity result is assumed. Pause stops between images; an already executing native operation may finish. MenuBarExtra keeps monitoring available while the Studio window is closed; quitting stops monitoring. There is no privileged daemon or launch-at-login registration.

A removed/replaced folder can invalidate a bookmark: the user must reselect it rather than bypass permissions. Scans/retries recover transient missing destinations and corrupt inputs after correction. Filesystem providers, disk-full races, power loss and signed sandbox behavior still require broader QA. Publication and ledger updates are not a single transaction; interruption in that narrow window can create safely numbered duplicate outputs on retry. App-owned orphaned snapshots may remain after interruption or workflow deletion; cleanup/storage UI is future work.

Export profiles merge authored source masks/annotations and privacy restrictions instead of discarding them. Framing resets retain adjustments and protective overlays; explicit Reset All is separate and undoable. Collage completion URLs are persisted/rebased and survive recovery. Staging uses O_EXCL creation with owned-file cleanup, so a pre-existing staging collision cannot delete the existing file. Local file-URL boundaries prevent image/project/watermark fetches through remote URLs. Imported symlinks resolve to independent validated regular snapshots. Normal Mac quit stops work and flushes the session; a save failure declines termination.

## Incremental source acquisition

Core SourceImporter is a separate actor from ImageProcessor: lazy enumeration, 1 MiB copy/hash chunks, bounded progress callbacks, local validation and immediate asset publication. Workspace stores transient import progress/task state; edits stay independent. Preview tasks operate on completed local snapshots while import continues. Mac BrowserDropImporter is an acquisition adapter for NSItemProvider image data/file URLs and explicit HTTPS downloads; it never moves networking into Core. See [browser/network import details](BROWSER_DROPS.md).

## Incremental acquisition and privacy review update

See [incremental import](INCREMENTAL_IMPORT.md) for publication and checkpoint scheduling, [privacy review](SENSITIVE_CONTENT.md) for transient state and capability gating, and [signing](SIGNING.md) for verified local-signing limits. Regression coverage includes editing during acquisition, 50,000 synthetic gallery records, temporary findings/filtering, source invalidation, manual flags, and sharing approval invalidation. Automatic Apple detection and actual large NAS throughput are not validated by these fixtures.

## Interface review

Gallery selection helpers update the shared scope directly; compact and regular layouts retain one editing snapshot. Touch thumbnail editing is a deliberate regular-width mode, while phone precision editing owns crop gestures. Progressive PhotosPicker acquisition uses the shared import-data path with task cancellation/progress; classification follows acquisition. Classification scheduling uses pending IDs and a forward cursor. See [UX review](UX_REVIEW.md).

Overlay editing now uses a Core draft session with local history and atomic, conflict-checked Apply. Drafts never enter autosave/export. See [Hide Something](HIDE_SOMETHING.md).

Privacy drafts are transient Workspace state backed by OverlayEditingSession. Main Mac/iPad and full-screen phone editors render the same draft; no overlay draft appears in ProjectDocument or export jobs. OverlayGeometry shares rotation-aware, normalized resizing.

## Scoped workflows revision

ConfigurationPatch serializes only named ConfigurationField values; EditingSnapshot overlays these onto shared settings. Legacy snapshots migrate relative to their saved batch configuration, with explicit dimension rules retained. Workspace field bindings apply patches separately to target IDs. UI workflow and active/group selection are separate from persistent edit state. ShareOutputSession freezes outputs for one completed operation and excludes accumulated export history. Encoded Output Preview and export share ImageProcessor.encodedData. See WORKFLOWS_AND_EDIT_SAFETY.md for scope, reset, profiles and migration rules.


## Library and tabbed Editor

The Photo Library is the gallery. Batch Edit, Editor, Collages and Mac Automations are separate workspaces sharing its sources and editing state. Privacy Review is a library filter; Privacy is an Editor tool, available from the editor toolbar or a photo’s context menu.

Mac and iPad Editor show explicit, closable photo tabs. iPhone uses an Open Photos menu. Tabs are unique per source and independent of gallery focus, filters and batch membership. Export/share targets only the active editor photo. Closing a tab preserves all project edits and original files; closing the last returns to the gallery. Optional tab IDs and the active tab are saved in schema-4 projects, with absent fields defaulting to an empty session in older projects. Per-tab tool context is retained during the current app session and starts at Adjust after reopening a project. Apply or cancel an overlay draft before switching tabs or workspaces.


## Multiple collages and art generation

SavedCollage wraps a named CollageProject. Workspace keeps open/active composition IDs independently of photo tabs and batch selection; histories are keyed by composition ID. ProjectDocument stores all compositions plus a legacy active composition for compatibility. CollageTemplate provides 74 deterministic layout descriptions and shares actual geometry with gallery diagrams. CollageShape uses shared Core Graphics/CoreText paths for cell and overall clipping. CollageArtBuilder is an off-main actor: integral-mask partitioning creates exact-count shape/text regions; photomosaic analysis builds ephemeral downsampled features and uses a colour kd-tree with local-pattern scoring and reuse control. No third-party model or network path is involved. ImageProcessor.renderCollage reuses the existing transform/overlay pipeline, sequential tile rendering, a bounded per-render cache and cooperative cancellation/progress. Export captures the active composition before awaiting render. See COLLAGES.md for limitations and validation.


### Review follow-up architecture

Project schema 4 remains extensible: optional `name`, `batchInputIDs` and `privacyCoverageReviewIDs` default safely for older projects. Processing definitions and existing effective edits are unchanged by loading. Fixed batch IDs are independent of live gallery selection. Privacy coverage review is distinct from Vision sensitivity classification and framing proposals; geometry changes flag masked photos and the flag survives framing resets/reopening.

Quick Fix captures per-source input configurations, computes asynchronously with cancellation, then merges only fields that have not changed since capture. All successful patches commit together as one named history step. CollageRenderIdentity compares only relevant sources/configurations and composition data to prevent stale previews/exports being presented as current. Existing exports remain immutable.

PixelZoomViewer takes actual full-resolution CGImage data for output-pixel inspection, with display-scale-aware 100%, fit and pan. Normal gallery/editor previews remain downsampled; detail rendering is explicit. Watermark bounds reuse the shared Core renderer. Crop and collage handles use shared geometry, with platform-specific pointer/touch adapters in SwiftUI. SourceStorageCleanup now also provides read-only owned-snapshot accounting; removal protections are unchanged.

### Composition output and review publication

Collage projects add optional output format/quality and outline font/layout-version fields. Missing text-layout version decodes to legacy geometry; new text art uses multiline outlines. Encoded composition proof and publication share Core encoding, explicitly flattening transparency on white for non-alpha formats. Reviewed destination copies validate encoded bytes and stage/exclusively publish without recompression. Collage privacy coverage review is independent of source-photo review.

## Workspace membership and creation ownership

`Workspace.assets` remains the sole source registry; `workspaceAssets` excludes optional schema-4 `hiddenSourceIDs` for ordinary gallery operations. Removing workspace membership preserves source ownership for current/saved GIFs and collages, including session histories. The shared renderers receive canonical sources, not a filtered gallery. Explicit working-copy cleanup scans current/saved instructions and watermark history before releasing unused UUID-named snapshots. See [current reliability review](RELIABILITY_REVIEW.md) for migration, recovery and verification details.

`GIFPreviewSession` owns only preview freshness/resources, not editing instructions. Concrete task destinations reuse the existing workspace selection context. New Convert operations use an optional native-output-sizing instruction; older configurations decode with the original sizing semantics.
