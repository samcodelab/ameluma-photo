# Ameluma Photo

**Your photos. Your way.** A native, local photo toolbox by Broad Frame Studio for macOS 15+, iOS 18+ and iPadOS 18+. Open `Framepebble.xcodeproj` and choose **FramepebbleMac** or **FramepebbleiOS**. Both targets link the same local `FramepebbleCore` Swift package; there are no third-party runtime dependencies.

## Product direction

A focused everyday photo editor: a smaller set of tools held to a high standard of usability and output quality. Single-photo tools belong on one persistent canvas with nearby options, stable zoom/pan and coherent history. See the [current product contract](docs/PRODUCT_SPECIFICATION.md) and [immediate priorities](docs/DEVELOPMENT_ROADMAP.md).

Retouch is currently local patch-based healing/cloning, not structural content-aware object removal. Complex removals crossing branches or object boundaries can leave fragments or damage texture; improving this is an open quality priority.

Single-photo tools now share session magnification and a normalized viewport centre. Crop and Watermark use the same view-zoom container; overlay tools are embedded without a nested navigation stack. Floating options are the default on wider screens, with an explicit pin action. Recolouring resolves pending edits before changing tools. Crop mode ends when another tool is selected. These changes preserve output geometry and batch inputs.

Interactive rendering has its own shared Core worker, separate from exports. Single-photo preview coalescing is 16 ms, with reduced resolution during adjustment gestures and refinement afterward. Preview-result and retouch-prefix caches are bounded to 16 MiB each, source/edit/resolution keyed, and cleared on lifecycle/private-mode transitions. Native signposts and bounded in-memory timing records cover canvas preparation, with superseded identities excluded. These measure image handoff, not display presentation or pointer latency.

The local exemplar-removal prototype fails photographic review on the bird tail/claws. It is absent from normal tool choices; Debug builds can expose it using `--experimental-removal` for development. Heal and Clone retain their existing recipes. Synthetic edge tests passing does not establish acceptable object removal.

See [editor implementation and verification evidence](docs/EDITOR_FOUNDATION_2026-10-17.json) for the measured environment, reproducible commands and remaining gates. Physical-device/Pencil testing, frame-presentation latency, an M1/8 GB performance baseline, a matched competitor benchmark and acceptable complex removal remain outstanding.

## Recipes and contextual actions

Use **Actions… (Command-K on Mac)** from the workspace or editor. Its scope is captured when opened: current photo, explicit gallery selection, captured batch inputs, layered document, GIF or collage. Creation actions never substitute a stale gallery selection. Supported local parameter commands include `resize to 1920`, `convert to PNG` and `filter Warm`; other actions expose existing tools. This is a deterministic local action system, not a general natural-language assistant. Draft editing keeps actions inside the draft until it is applied or cancelled.

**Recipes** is a visual builder for Corrections → Resize → Filter → Watermark → Output, using the existing processing engine's canonical order. Enable only needed steps, preview the first captured photo, save a named recipe, then apply it to the stated inputs. Recipes store independent parameters, not crop positions, source IDs, retouch, annotations, colour traces, resolved Auto Enhance or destinations. Each photo keeps its unrelated edits and grain seed. Watermark capture is an explicit action; image assets become owned local recipe resources. Conversion alone preserves existing dimensions; resizing is a separate enabled step. Older processing profiles and automation recipes retain their existing meaning.

Application reports changed/skipped/failed/not-run counts, skips concurrently edited sources, and supports cancellation and grouped Undo for committed changes. Retry is explicit. Recipes are local app data, not portable cross-device projects. Owned recipe assets are retained after deletion because current photos, saved work or Undo may still use them. Step reordering and an Auto Enhance analysis step are not included.

The Mac layered editor's **Use Result** menu adds a flattened finished image to Workspace or starts a GIF from it, preserving the editable document. The new source has an independent baseline even through existing Undo history. **Export Changed Photos** from Recipes freezes only successful changed targets and their export configurations; later selection or editing cannot alter the queued request. Saving editable documents remains separate from exporting finished images. Multi-element watermark authoring remains Mac-first; iPhone/iPad can import and apply saved designs.

See the [review and follow-on phase report](docs/WORKFLOW_PHASES_3_5_2026-10-17.html) for current screenshots, test outcomes and verification limitations. The 24-filter collection is unchanged.

## Implemented workflows

- Import multiple files, recursive folders, Finder drops and item-based Photos selections. Native decoder capabilities determine JPEG, PNG, HEIC, TIFF and WebP availability; input validation uses content, not extensions.
- Browse the lazy grid, find actual Vision-classified content, filter favourites/edited/review images, and select matching images.
- Switch to **Frame**, drag inside fixed output thumbnails, pinch or Option-scroll to zoom, then **Refine** for precision controls. Grid and precision editing use one normalized crop state. Compare original and processed views with the comparison slider.
- Resize using Fit, Fill, Stretch, Canvas or Preserve Aspect Ratio; choose custom pixels or presets, prevent upscaling, rotate, flip and straighten. Scope controls apply settings to the whole library, selected images, search results or the current image.
- Use native Vision Smart/Keep Subjects framing and review flagged results. Batch auto-framing preserves manual overrides; explicit per-image Smart actions can replace them. Undo/Redo and explicit resets are available.
- Add text or image watermarks with relative sizing, colour, opacity, rotation, nine positions, offsets, margins and tiling. Save watermark and export presets.
- Export using registered native encoders, quality presets, optional bounded target-size encoding, supported metadata policies and sRGB/source-RGB colour management. Export one or multiple profiles into separate folders.
- Adjust exposure, brightness, contrast, saturation, warmth, highlights and shadows. Quick Fix uses bounded lighting/colour heuristics and native automatic suggestions; all corrections are editable and undoable.
- Create multiple tabbed collages with 74 gallery layouts, shape/text art and local reference photomosaics; reframe cells, swap/add/remove photographs, adjust backgrounds/spacing/borders/corners/shadows, and add titles/captions. Collages remain editable until rendering.
- Draw text, arrows, lines, rectangles, ellipses and freehand annotations. Hide selected areas with opaque covers, blur, pixelation or frosted effects; use precision cropping to exclude unwanted content.
- Review final outputs before native sharing, exclude files, approve a selection, copy a processed image, save reviewed images to Photos or reveal files in Finder. Sensitive-content detection is not enabled in this unsigned build; manual review does not certify safety.
- Configure Mac folder Automations using security-scoped bookmarks, reconciliation scans and FSEvents hints. Automatic/review modes, stable-file checks, hash history, retry, test preview and menu-bar monitoring use the Studio engine.
- Save/open project instructions, browse recent local projects and relink selected missing sources. Private mode bypasses memory thumbnail caching and offers workspace concealment. Repeated byte-identical imports can be skipped or imported anyway.
- Retain validated outputs through cancellation and partial failures; retry pending requests. Sources, edits, classifications, presets and pending export requests are saved locally for session restoration.

## Project layout

```text
Apps/macOS/          Native panels, Finder drop, sharing, FSEvents and automation adapters
Apps/iOS/            PhotosPicker, Files, Photos saving and lifecycle adapter
Apps/Shared/         MainActor session coordinator
SharedUI/            Library/grid, framing/precision, comparison and inspectors
Packages/FramepebbleCore/
  Sources/           Models/history, processing, adjustments, overlays, collages, privacy, Vision, search, watermarks, persistence
  Tests/             Shared geometry, codecs, Vision, watermark and export tests
Tests/               App interface-state, 100-image and native automation integration tests
Framepebble.xcodeproj Native targets and app-hosted Simulator test scheme
tools/               Standard-library project generator
docs/                Architecture, specification, roadmap, test plan, help and privacy
```

The checked-in project opens without a generator installation. `python3 tools/generate_project.py` regenerates it deterministically. Signing teams and App Store records are deliberately unconfigured.

## Build and test

```sh
swift test --package-path Packages/FramepebbleCore
xcodebuild -project Framepebble.xcodeproj -scheme FramepebbleMac -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Framepebble.xcodeproj -scheme FramepebbleiOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Framepebble.xcodeproj -scheme FramepebbleMacTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Framepebble.xcodeproj -scheme FramepebbleCoreiOSTests -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Choose an installed Simulator. Swift 6 language mode is used with installed Xcode 27 / Swift 6.4. The macOS gesture adapter uses isolated deinitialization, supported by this compiler. See [TEST_PLAN](docs/TEST_PLAN.md) for evidence and required release checks.

## Safety and privacy

Processing always starts from an unchanged private source snapshot. No images are uploaded by Framepebble. No accounts, advertising, analytics or telemetry are implemented. Mac browser drops can download an explicitly dragged HTTPS image link when the browser does not supply image bytes; cookies, stored credentials and local images are not sent. Editing and local imports work offline. A serial renderer, bounded thumbnail cache and downsampled editing surfaces control image memory. Local source snapshots use disk space once per import and currently remain in Application Support until removed outside the app.

Exports are staged on the destination filesystem, decoded for validation and published with an exclusive rename. Source aliases and existing names are never replaced. Unsupported publication operations fail visibly. Metadata policies copy or remove selected supported dictionaries; they do not guarantee anonymity or universal metadata removal. JPEG and HEIC outputs flatten alpha.

PhotosPicker, Files and Share are Apple-managed services. iCloud-only selections may be downloaded by the system; an explicitly selected cloud destination or Share action may synchronize at the user's direction. Local processing works offline with locally available files. Photos saving requests add-only permission. See [PRIVACY](docs/PRIVACY.md).

## Current limits

This is a substantial development build, not a completed commercial release. Physical-device performance, Pencil/trackpad testing, sandbox/signing validation, VoiceOver/localization, large real-world collections, provider-specific atomic publication, Photos format support and catastrophic interruption recovery still require QA. Project copies and relinking are implemented; storage accounting/cleanup and comprehensive bookmark repair remain unfinished. There is no arbitrary semantic search, foreground-mask framing, export-profile destination bookmark UI or universal WebP encoder. No unavailable features are presented as working controls. See [roadmap](docs/DEVELOPMENT_ROADMAP.md).

Release targets now share `com.broadframestudio.framepebble`. Debug retains the earlier Mac/iOS identifiers to preserve development data. Apple's current [universal-purchase guidance](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms) requires the same bundle ID and shared app record; configure a single shared App Store record and signing team before distribution. No App Store records were created.

The intended business model is a one-time universal purchase at a target A$29.99. No store price, purchase record, subscription or in-app purchase has been configured. See [latest implementation report](docs/TOOLBOX_IMPLEMENTATION_REPORT.md).

The latest interface simplification and outstanding usability checks are documented in [UX review](docs/UX_REVIEW.md).

App Store submission is on hold; see the [reviewer audit](docs/APP_STORE_REVIEW_AUDIT.md) for fixes, unsigned archive evidence and remaining release gates.

Mac accepts browser image-data drops and explicitly dropped HTTPS image links, alongside Finder files and nested folders. Web-only downloads are capped at 25 MB; inaccessible/login-protected pages should be saved in the browser first. See [browser drop support](docs/BROWSER_DROPS.md).

Network-folder import now copies and hashes each source in one pass on a separate acquisition actor. Images appear and can be edited incrementally; a pinned progress strip reports copying, discovery and cancellation. Server/network performance still limits transfer speed.

Recent implementation details: [incremental imports](docs/INCREMENTAL_IMPORT.md), [temporary privacy review](docs/SENSITIVE_CONTENT.md), and [local signing](docs/SIGNING.md).

## Preview size and workspace cleanup

Use Preview size above the gallery to enlarge or shrink tiles. This changes display size only; exported dimensions and crop geometry are unchanged. In Projects, Close Project saves work to Recent Projects and empties the workspace. Clear Imported Photos discards current edits after confirmation, stops processing, saves an empty session and removes unused UUID-named regular snapshots only from Framepebble’s private Sources folder. Originals, exports, saved project files and snapshots they reference are retained. Symlinks and unknown filenames are skipped. An unreadable saved project stops cleanup. There is no secure-deletion claim. To preserve current edits, save a project copy before clearing.

Cross-platform interface review and validation limits: [UX review](docs/UX_REVIEW.md).

## Four workflows and scoped edit safety

Batch Edit, Editor and Collages share one library; Mac also offers a dedicated Automations workspace. Field-scoped overrides prevent unrelated photo edits from being overwritten and retain batch inheritance. Schema 4 migrates versions 2/3 while preserving effective output. Sharing sessions contain only successes from the requested operation. Export plans include profile counts and final-resolution encoded previews. See [workflow behaviour and limits](docs/WORKFLOWS_AND_EDIT_SAFETY.md).

The completed UI/UX polish pass and native layout captures are documented in [UI_UX_COMPLETION_AUDIT.md](docs/UI_UX_COMPLETION_AUDIT.md), including physical-device, accessibility and release-validation limits.


## Workspace and tabbed Editor

Workspace is the imported working area. Batch Edit, Editor, Collages and Mac Automations are separate workspaces sharing its sources and editing state. Privacy Review is a library filter; Privacy is an Editor tool, available from the editor toolbar or a photo’s context menu.

Mac and iPad Editor show explicit, closable photo tabs. iPhone uses an Open Photos menu. Tabs are unique per source and independent of gallery focus, filters and batch membership. Export/share targets only the active editor photo. Closing a tab preserves all project edits and original files; closing the last returns to the gallery. Optional tab IDs and the active tab are saved in schema-4 projects, with absent fields defaulting to an empty session in older projects. Per-tab tool context is retained during the current app session and starts at Adjust after reopening a project. Apply or cancel an overlay draft before switching tabs or workspaces.


## Product naming

The application is **Ameluma Photo**. Its iPhone/iPad home-screen display name is **Ameluma**. The Mac app bundle is `Ameluma Photo.app`; the iOS bundle is `Ameluma.app`. Xcode project/target names, Swift modules, bundle identifiers, security-scoped references and legacy Application Support locations retain their existing Framepebble identifiers for compatibility. No source or saved-project migration is required for this branding change.

See [Collage tools and limits](docs/COLLAGES.md) for photo-filled shapes/text, reference mosaics, persistence and export behaviour.

The [workflow review implementation ledger](docs/REVIEW_ACTIONS.md) records the latest usability changes, verification and remaining limitations.

## Workspace and animated GIFs

Workspace is the imported working area, not a synchronised photo catalogue. Date, format, orientation, filename and existing Vision-label filters retain hidden selections. Actions capture explicit inputs; context actions distinguish the clicked photo from a selected group. Remove from Workspace changes visibility while retaining source ownership for creations. Original files are never deleted.

Create GIF starts from Tools or Workspace → Actions. Its photo picker restores the previous selection and filters on Cancel. GIFs capture photo edits independently, support ordered/duplicate/reordered frames, individual/group/all-frame timing, cropping, Fit/Fill, canvas sizes, captions, arrows, rectangles, ellipses and speech bubbles. Annotation visibility supports This Frame, Until Removed and All Frames. Preview and native Image I/O export share frame composition and centisecond timing. New creations retain earlier GIFs under More → Saved GIFs; workspace/session copies include unfinished GIF instructions.

GIFs support 1–1,000 frames, 16–2,000 pixels per side, 0.1–60 seconds per frame and finite/forever looping. Optimisation presets change dimensions; native palette encoding can introduce photographic banding. Size is measured after encoding. Export renders frames sequentially, validates every encoded frame and publishes without replacement. Reviewed Files copies preserve the animation bytes; GIFs require manual review of all frames. Physical-device performance and gesture verification remain release checks. See [implementation and validation](docs/WORKSPACE_GIF.md).


Current reliability work and verification: [review results](docs/RELIABILITY_REVIEW.md). Project instructions reference local files and are not self-contained cross-device packages. New Convert tasks preserve source dimensions unless Also Resize or an explicit output profile is selected; legacy projects retain their saved output. Workspace removal keeps creation dependencies, and Free Unused Working Copies is separate from clearing current work and creations. GIF missing-frame recovery, saved-creation access, relinking review flags and duplicate detection follow current project ownership.

## Demo Workspace

Choose **Open Demo Workspace** from the workspace sidebar, Projects, or iPhone home screen to try 30 generated sample photographs in a separate saved editing session. Use **Return to Your Workspace** to resume your own photos and edits. The collection includes a colourful bird hero, polished coastal and golden-light portraits, and five deliberately imperfect editing challenges. See [Demo Workspace behaviour and verification](docs/DEMO_WORKSPACE.md) and [asset provenance and usage](Resources/DemoWorkspace/README.md).

Creative Filters uses a versioned catalog of 24 original SDR recipes, independent persisted Auto Enhance, scoped history and captured batch inputs. Native kernels and the shared renderer drive thumbnails, canvas and export; legacy six-look edits remain compatible. See the filter delivery report for measured hardware, validation evidence and release limitations.

### Inline colour replacement and edge refinement (17 October 2026)

Replace Colour is a dedicated toolbox tool (under Tools on iPhone), using the existing editor canvas rather than an adjustment or separate editing sheet. Tracing shows a live translucent selection with a contrasting outline. A single bounded, session-and-edit-keyed editor preview is reused across matching tool entries; changed sources or edits never reuse an unrelated image. Apply and Cancel affect only its captured single-photo draft. Select Object uses local Apple Vision foreground instances with sampled-colour guidance; Trace followed by Refine Edges restricts detection to a rough area when adjacent objects are grouped. New feathered selections remain inside their boundary; older saved replacements retain their original feather rendering. Significant detected cutouts are saved as normalized contours, so preview, export and reopening share the selection.

Automatic selection is approximate, not guaranteed object or garment recognition. Similar colours, connected objects, fine hair, transparency and patterned materials need review or manual tracing. On the tested iPhone Simulator, Vision could not create an inference context: the selection diagnostic is skipped and Trace remains available. Physical iPhone/iPad validation is still required. All processing stays local.

### Retouch stroke revision 3 (17 October 2026)

New UI-authored retouch strokes use whole-path automatic sampling: candidate source translations are scored against the surrounding path and rejected if they overlap the removal area. Heal estimates low-frequency tone from outside the painted coverage rather than blending the unwanted content back in. Version-1/2 saved strokes keep their historical rendering. This remains local texture-based healing, not semantic scene reconstruction; complex structural edges and large removals need review or a manual Clone source.

Mac painting uses native mouse-down/drag/up tracking inside the canvas. An isolated native mouse test on the kitchen demo confirmed a real drag produces a multi-point stroke. The opt-in `AMELUMA_NATIVE_BRUSH_CHECK=1` test-action environment flag enables that interactive test; use a separate test host when another editing session is open. The 1,000-pixel kitchen diagnostic measures source matching and rendering separately; these warm test timings are not release p95 or physical-device performance claims. Physical touch/Pencil and very large images still require verification.


### Editable image documents — initial Mac implementation (17 October 2026)

File → **New Image Document** creates a transparent canvas. **Open Selected Photos as Layers** captures the chosen workspace photos and their effective edits; **Duplicate Current Photo as Document** captures the active photo. Document commands never use live batch selection after creation. Use File → **Open Documents** to resume an open document after returning to Workspace.

The initial document editor supports raster image placement/drop/paste, editable text and basic shapes, independent layer transforms with handles and numeric fields, ordering, duplication, visibility, locking, opacity, eight blend modes, thumbnails and document-local Undo/Redo. Fit/actual-pixel viewing, pinch/Option-scroll zoom, native scrolling, independent canvas dimensions and a display-only checkerboard are included.

**Save** writes a version-1 `.ameluma` package containing the editable model and immutable image resources. It remains usable after the source workspace is cleared. Editable packages contain their original image resources; **Export** or **Copy Flattened Image** produces the finished image instead. Export shares the existing encoding, validation and collision-safe publication path. Local recovery preserves unsaved content, saved location and dirty state. Older workspace project instructions retain their existing format and local-reference semantics.

This is the first stage of the approved general-purpose editor plan, not the whole roadmap. New document authoring is currently Mac-only; Core models/rendering/storage compile and run on iOS/iPadOS. Existing mobile photo editing remains intact. New documents use SDR sRGB; HDR development, arbitrary document profiles, groups/merging, raster painting/eraser/fill, general region selections, adjustment layers, effect stacks and guides remain later stages. Per-layer photo recipes are captured, not yet editable through a new layer adjustment inspector. Normal photo adjustment/filter tools remain available in the existing photo editor.

Validation and remaining real-input/performance/accessibility gates: [document editor implementation report](docs/EDITOR_DOCUMENT_IMPLEMENTATION_2026-10-17.html).

### Editable annotations and saved watermark designs

In the workspace action menu, **Annotate Photo** opens editable text, arrows, shapes, freehand strokes, translucent highlights and numbered callouts. Callouts renumber when reordered or removed; Undo restores their editable objects. Opaque privacy covers remain separate from translucent highlights.

On Mac, open **Watermark → Watermark Designs…**, choose an original template, then edit its ordinary text, shape and image layers. The Canvas name field names the reusable design. **Save Design** (or Command-S) saves its editable package locally; **Back** returns to the photo or batch without changing selection. **Save As…** can save a portable `.ameluma` copy. Preview backgrounds are never exported.

Choose a saved design and **Apply to N Photos** to replace only watermark content on those captured targets. Placement, size, opacity, rotation and tiling remain independently editable. Application is one undoable operation; later design changes/deletion cannot alter applied stamps. Vector design elements render at the requested stamp size, bounded to 16 megapixels; raster logos retain their original resolution limits. iPhone/iPad can import and apply saved designs; multi-element design authoring currently requires Mac. Designs use document version 2; existing version-1 documents and legacy text/image watermarks remain supported.

See [phase delivery evidence](docs/PHASES_0_2_IMPLEMENTATION_2026-10-17.html) for test outcomes, native captures and remaining verification.
