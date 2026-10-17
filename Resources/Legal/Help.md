# Using Ameluma Photo

## Photo filters

Choose **Filters** in the Editor toolbox. There are 24 original presets in Essentials, Film, Cinema and Monochrome, plus Original. The Mac inspector shows a two-column grid; iPhone and portrait iPad show a compact photographic strip. No third-party preset definitions, LUTs or branded film emulations are bundled. Names are working product names, not a claim of trademark clearance.

Choose a preset, then adjust **Intensity** from 0–100%. The first selection starts at 70%; switching presets retains the current intensity. Candidate tiles show 70%; the selected tile reflects its current intensity. Original and Reset Filter remove only the creative look. At 0%, the selected look remains saved but is bypassed exactly. Older six-look projects retain their original rendering until you explicitly choose another look or Original.

**Auto Enhance** is an independent correction. Its resolved native adjustments are saved; changing other edits does not rerun analysis. Use Recalculate Enhance explicitly. Original does not disable Auto Enhance. Hold **Compare** to bypass Auto Enhance and the creative look while retaining all other edits; an accessibility action toggles this comparison. The editor’s separate Original comparison shows the source appearance.

Workspace Actions → **Apply Filter to Selected…** captures explicit inputs. Confirm the preset and percentage before replacing only their creative filters. Validation is incremental, then successful instructions publish together as one atomic editing/history change. Cancel stops scheduling and keeps validated changes; results report completed, skipped and failed photos. Newer edits are skipped. Retry Failed or Skipped explicitly captures those photos again. Auto Enhance remains a separate operation and analyses each photo independently.

Processing stays local. These presets are SDR looks in an sRGB half-float working pipeline; HDR/gain-map sources are rejected until a versioned SDR development step exists. Standard supported JPEG, PNG, HEIC, TIFF and natively supported WebP inputs use the same renderer for preview and export. Unsupported recipes block affected rendering/export and remain preserved in saved projects; choose Original to recover. Source files remain untouched. Projects with new filters need a supporting app version to reproduce them.

On iPhone, start with Edit a photo or Prepare a batch. Resize and Convert are compact quick tasks; Retouch and Privacy remain tools inside the Editor. Right-click or long-press one photo for Retouch Photo. Task selection keeps unrelated workspace selection and captured batch inputs. Empty workspaces offer the Demo Workspace; on iPhone, Back to Start returns to the task choices.

After a photo or batch export, the completion card lists only successful files from that operation. Review & Share opens those files for manual approval; Show in Finder is available on Mac. A cancelled operation keeps completed files, and a wholly failed new export does not reuse old files. The completion card is temporary and disappears when dismissed or when a new export or project begins. Existing export history remains separate.

Editing panels follow the current task. On Mac, the sidebar button makes more room for the photo; inspector tools use icons with help and accessibility labels. On iPhone, choose a tool below the photo to show its controls. At accessibility text sizes, use the expanded Tools presentation. Open photos, editing targets and batch inputs remain separate.

Fresh workspaces start at 100% original dimensions with no canvas padding. Existing saved projects and presets retain their output. Choose a fixed size preset or another sizing mode explicitly to resize or add a canvas. In wide editors, common options sit near the tool rail; close them when they cover the photo and tap the tool to show them again. On a phone, tapping the active Adjust tool hides or restores its compact controls. The full inspector remains available from its settings button. Batch Inputs/Workspace changes only which thumbnails are shown, not selection or captured operation inputs. The Demo menu identifies the sample workspace and returns to your own workspace after current operations or drafts finish.


In iPhone landscape, photo tools move to a side rail and document controls move into the navigation bar. Small or short screens open expanded controls to preserve room for the image. GIFs use a frame chooser and Tools menu when the full strip and inspector will not fit. Collage Export opens output options before creating the file.

The Mac collage inspector groups Canvas, Appearance and Title controls. Title opens automatically for compositions that already contain one; collapsing it keeps the title. Fit and the viewing zoom buttons change only the workspace view, not output dimensions. Inspect Pixels in collage Actions opens full-resolution inspection. Shape, text and photo-mosaic creation remain in Actions → Create.

The operation heading identifies the photos affected by Batch Edit or Convert. Change Photos changes those inputs explicitly. Filtering, switching Mac editor tabs or opening another photo on mobile does not change captured inputs. Workspace selections use checkmarks; the active photo has a separate focus outline. Gallery actions include Show filenames for a cleaner thumbnail view.

Export opens the output options for the current task. Conversion retains source dimensions unless Also Resize is enabled. GIF Timing, Canvas and Text panels distinguish frame settings from animation settings; Select Frames enables multi-frame timing changes. Collage properties distinguish the whole composition, the selected photo and output settings. Saved Collages and Choose Layout are separate views. Missing GIF sources can be replaced directly from their recovery action without opening project housekeeping.

Import photos/files or a folder. The app makes local source copies and begins on-device classification. Existing editing settings remain in place when adding images.

Use the search field for recognized label words such as dog or beach; suggestions show labels actually found. Combine words only when both labels are present. Search is not arbitrary language understanding. In Batch Edit, choose the labelled inputs: all images, selected images or search results. Editor always acts on its visible current photo. Select visible results from the More menu to edit/export only matches.

Browse navigates originals. Frame shows output-shaped thumbnails; drag within an image to reposition it. Pinch or hold Option while scrolling to zoom. Normal Mac scrolling navigates the grid. On touch devices, Frame is a deliberate manipulation mode; switch to Browse for easy scrolling. Double-click on Mac or use Refine to open larger precision controls. The same position/zoom state appears in both surfaces. Before/after and guides help judge the result.

Choose a size preset or enter pixels. Fit keeps the full image with padding; Fill crops to fill the output; Stretch distorts; Canvas adds alignment/background options; Preserve Aspect Ratio calculates the other dimension from the chosen basis. Crop presets change output dimensions. Prevention of upscaling can leave padding. Rotation/straightening can expose background or change subject placement, so review affected images.

Smart and Keep Subjects use native spatial detections/saliency. Batch automatic actions keep manual overrides. Per-image Smart/Keep Subjects intentionally replaces that image's manual crop. Review the Needs Review category and use Previous/Next to inspect it. Accept a proposal, refine manually, or reset/centre it. Vision can be wrong even when no review flag appears.

Choose Add Watermark to enable a text/image watermark and configure its relative size and opacity. Remove is beside the watermark heading and supports Undo. Expand Placement & pattern for anchor, rotation and tiling. Logos are copied locally. Watermark presets and full export presets are saved locally. Processed previews retain watermarks and other treatments while framing; Updating processed preview identifies a render still catching up. JPEG/HEIC flatten transparency; use PNG/TIFF when alpha is needed.

Choose quality or a target KB limit. The encoder searches within a minimum-quality floor and fails if the requested size is infeasible. Reduce output dimensions or raise the limit rather than expecting arbitrary images to fit any size.

Leave export-profile checkboxes empty to export current settings. Select multiple profiles to create separate folders. Manual image framing continues to apply. Naming tokens are {name}, {suffix}, {id}. Original/existing files are retained and collision names are numbered. Export shows progress, supports cancellation and reports individual errors. Retry unfinished requests after selecting a destination. Completed results can be shared. iOS Photos additions require the system permission and depend on format support.

The local session restores sources, edits, analysis and pending work after relaunch. Re-select an external destination when retrying after relaunch. Originals remain unchanged. Keep important output files in a permanent Files/Finder destination; the local session is not a backup or cloud service.

## Everyday tools

Choose Batch Edit, Editor or Collages on iPhone/iPad; Mac also offers Automations. These share the same library and preserve edits when switching. Import images if needed. More Tools opens contextual Frame, Adjust, Create and Export controls. Rotate acts on the selected photograph; use Refine for position/zoom/crop or Compare for original/processed output.

Adjust sliders show neutral values and individual resets. Quick Fix applies conservative automatic suggestions; no change can be appropriate. Always preview coloured scenes before accepting a colour correction. Undo restores the earlier settings.

## Collages and overlays

Use Collages and Choose Source Photos independently of batch inputs, choose a quick layout or open the 74-layout gallery, select a cell and drag its photograph. Zoom/position controls provide alternatives. Change its source or swap with the next cell; freeform adds placement/rotation. Add titles/captions, spacing/background/borders/corners/shadows, then render and review/share. The project remains editable.

Privacy Review is a library filter for flagged photos. Privacy is a tool inside Editor. Right-click (or long-press) a photo and choose Edit with Privacy Tool; flagged photos use Reveal & Edit with Privacy Tool. If nothing is flagged, show All Photos and flag or edit a photo from its context menu. Automatic findings require Apple’s capability and system settings; manual flags remain available.

Privacy editing uses the main Mac/iPad workspace and a full-screen iPhone editor. The editor keeps a draft until Apply. Drawing selects the new area immediately; click empty photo space to return to Draw. Select chooses existing areas; drag their bodies to move them or their eight handles to resize. Change the selected effect or use the numbered area controls. Undo, Redo and Delete stay with the tool controls. Cancel, Escape and Close Editor discard all changes made during this editing session, preserving any previously applied masks. Apply commits the draft as one project Undo step. Switching from a changed privacy/annotation draft to another tool offers Apply or Discard; on Mac and iPhone, Apply & Crop also explicitly applies the draft before opening precision cropping. New privacy areas start with Pixelate and Freeform. Trace around an area and lift to close its outline; incomplete straight-line traces do not create a mask. Rectangle, ellipse and other effects remain available, and existing areas keep their saved settings. Annotations support basic fonts/alignment/colour. Inspect the final output before sharing.

Opaque covers and cropping offer stronger concealment than blur/pixelation. Masked exports flatten the pixels and omit copied source metadata. Do not share editable project instructions when you intend to share only a concealed image.

## Review, projects and private editing

Prepare to Share renders final outputs into local Exports. Review concealed previews, exclude unwanted files, approve the selection, then share/copy/save reviewed images. Changing inclusion requires new approval. Privacy Review lets you flag, filter and reveal photos before opening masking or cropping. Optional automatic checks use Apple Sensitive Content Analysis only when the capability and system settings permit it; otherwise manual review remains available. Checks before sharing analyse the final outputs. Approval is your decision, not a safety certification.

Projects saves a local copy of source references and editing instructions. New project preserves the previous workspace first. Open a recent or selected JSON project; relink a missing selected source to the corresponding original. Cross-device project files may need relinking. Sources are never automatically deleted.

Private mode bypasses memory thumbnail caching. Conceal covers the workspace; iOS also conceals when backgrounded. Saved originals/edits/exports remain for recovery; no secure deletion/encrypted vault is promised.

## Mac folder workflows

Open Automations, create a recipe, choose separate authorised input/output folders, configure Studio settings/action toggles and choose Automatic or Review Before Export. Privacy review always requires manual approval in this build. Enable monitoring and add an image. Transfers must stabilize and decode before processing. Run Now reconciles; Test previews a sample without writing the destination. Pause finishes the current native operation before stopping new images.

The menu bar remains available with Studio closed. Quit stops monitoring. Missing/replaced/revoked folders may require selecting them again. Correct a failed input or destination, then retry. Inputs/outputs cannot overlap or feed another workflow. No login item or background daemon is installed.

## Browser images and network folders on Mac

Drag the image itself from a browser. Ameluma Photo uses supplied image bytes first, or downloads an explicitly dropped HTTPS image address without browser cookies or saved credentials. Browser downloads are limited to 25 MB. Login-protected, HTTP-only or page links may need to be saved in the browser first.

File/folder imports show copy progress below the grid. The first completed image appears immediately; further arrivals are published in batches of at most 64, with a 150 ms publication timer. you can scroll, crop and reframe them while the remaining files copy. Folder totals are discovered as the import runs. Cancel retains completed images. A stalled NAS read may take time to respond to cancellation. Vision search indexing starts after acquisition finishes.

## Preview size and workspace cleanup

Use Preview size above the gallery to enlarge or shrink tiles. This changes display size only; exported dimensions and crop geometry are unchanged. In Projects, Close Project saves work to Recent Projects and empties the workspace. Clear Imported Photos discards current edits after confirmation, stops processing, saves an empty session and removes unused UUID-named regular snapshots only from Ameluma Photo’s private Sources folder. Originals, exports, saved project files and snapshots they reference are retained. Symlinks and unknown filenames are skipped. An unreadable saved project stops cleanup. There is no secure-deletion claim. To preserve current edits, save a project copy before clearing.

## Gallery and selection

Browse shows originals; Frame shows the intended output; Compare shows before and after. Select changes Workspace selection. Captured Batch Edit and Convert inputs remain fixed; use Change operation photos to replace them explicitly. Check the labelled count before export. On iPhone, open Refine for touch cropping. On iPad, Frame → Reframe thumbnails deliberately enables dragging/pinching the selected photo; Done Reframing returns to normal gallery scrolling. The inspector adapts to available space. Search categories come from Vision and can be wrong or incomplete.

Drawing now immediately selects the new mask or annotation. Clicking the selected area keeps it selected; clicking empty photo space clears selection and returns to drawing without creating an extra object. The next drawing keeps the last selected effect/shape or annotation kind. Verified with live Mac synthetic-image interaction.

## Workflow targets, inheritance and output proof

Editor shows a large processed preview of one named photo; its export/share produces one current-edits rendition. Batch Edit shows its input scope and photo count. On Mac, Command-click toggles batch selection, Shift-click selects a range and Command-A selects visible photos with gallery focus. Arrow navigation changes the active photo, preserving group membership. Changing filters retains selected photos hidden by the filter and chooses a visible active photo. All images explicitly targets the visible workspace membership, including photos outside the filter; choose Search results to limit the batch to that filter.

Inspector changes affect only the changed fields. Individual edits inherit untouched batch settings. Mixed values are listed; controls represent the first target until changed. Reset Active Photo’s Overrides restores chosen categories to batch inheritance. Copy Chosen Edits lets you select categories; Paste changes only those categories. Context-menu actions name the clicked photo or selected group.

The export plan shows photos → files · profiles and each profile's format, requested dimensions, naming and destination. Preview a profile to inspect final-resolution encoded output and exact byte count, including target-size compression. Large previews may take time. Privacy masks and annotations remain flattened in output. Export/share includes only successful files from that operation, reports partial failures and opens no sharing session on total failure. Export history and collage history remain separate.

Projects now use schema 4 and load versions 2/3 without changing effective edits. Legacy differences are retained as overrides; reset only categories you want to inherit anew. Older builds cannot read schema-4 projects.

### Exact adjustment values

Use the slider or type a number beside an adjustment. Values stay within that adjustment’s supported range. Mixed means the selected photos currently have different values; changing that control changes only that adjustment. The reset arrow restores its neutral value for the labelled targets and leaves other edits intact.

### Precise area placement

Select a privacy area or annotation and focus the canvas. On Mac, arrow keys move it by a small step; Shift-arrow moves it farther. Movement stays inside the output and preserves its size, rotation and effect. Undo reverses a held key as one operation. VoiceOver canvas actions also offer movement in each direction.

To resize a selected privacy area or annotation without changing its proportions, enable **Keep proportions**, then drag a handle. On Mac, Shift-drag temporarily keeps proportions. Edge handles resize both dimensions around the opposite edge midpoint; corner handles keep the opposite corner fixed until the canvas boundary requires clamping.

### Start in the gallery

Choose **Workspace** in Workspace to see the full gallery. On Mac, double-click a photo to open Editor; on iPhone tap it outside selection mode. Right-click or long-press for **Open in Editor** or **Edit with Privacy Tool**. Use **Back to Workspace** to return on iPhone and iPad, or **Workspace** on Mac. Select multiple photos and choose **Batch Edit Selected** for a batch. Browsing does not reset edits, and the library’s project/clear actions never delete original files.

### Editor tools

Use **Adjust**, **Crop & Frame**, **Resize**, **Annotate**, **Privacy**, or **Watermark & Format** above the photo. The photo moves only while Crop & Frame is active, so adjusting lighting cannot accidentally change framing. On Mac and wide iPad, framing controls act on the large main preview. Original is a comparison view; choosing Crop & Frame returns to the processed result. Mac uses compact closable photo tabs. iPhone and iPad edit one photo at a time: use Back to Workspace, then choose another photo. Numeric crop positions use percentages. Batch inheritance and category reset controls are available under the defaults/overrides disclosure.

### Larger text on iPhone

With accessibility text sizes, Editor keeps the filename in the navigation toolbar, moves comparison and history into the photo menu, and offers editing tools through **Tools**. Adjustment values move onto their own full-width row. Gallery controls stack vertically, keeping the photo and selection actions readable. Use the compare button’s VoiceOver label to switch between the original and edited view.

When the editing toolbar cannot fit, use **More** for the remaining tools. At accessibility text sizes, use **Tools**. The gallery’s action menu also contains photo editing, privacy, preview size and Undo/Redo controls when larger text makes separate rows impractical. **Use Batch Framing** removes only the current photo’s framing override.


### Editor navigation and privacy tools

Open a workspace photo in Editor. iPhone and iPad show one photo at a time, with Back to Workspace in the navigation toolbar. Returning keeps edits, workspace selection and captured batch inputs. Choose another photo from the workspace to edit it. Apply or Cancel a drawing draft before leaving.

On Mac, photos use compact closable tabs. Reopening a photo activates its existing tab; closing it retains its sources and edits. Command-W closes the current tab. Legacy saved open-photo IDs remain compatible on every platform.

Privacy is an Editor tool; Privacy Review remains a gallery filter. Right-click/long-press **Edit with Privacy Tool** opens that photo with Privacy active. Apply or Cancel the draft before navigating. Workspace filtering retains hidden selections; the summary reports their count.


### Restore an original photo

In Editor, open **Edits** in the photo header and choose **Restore Original…** (on iPhone or at accessibility sizes, use the photo-name menu). Confirm to restore the active photo’s uncropped, unrotated appearance and native dimensions, removing lighting/colour adjustments, canvas effects, watermarks, annotations and privacy masks. Other photos and batch defaults remain unchanged. Export format, compression and metadata protection remain as configured. The Original comparison toggle only previews the source; Restore Original changes the editing instructions. Undo brings back the previous edits. Neither action modifies the original file.


### Expand a crop back to the full image

In Crop & Frame, choose **Reset Crop · Full Image** (also available as **Original · Full Image** in Output aspect ratio). This reveals the complete source at native dimensions while retaining rotation, adjustments, watermarks, masks, annotations and export settings. Undo restores the previous crop. **Use Batch Framing** instead returns to inherited batch framing; **Restore Original** removes all visual edits. Crops never discard the source pixels. Masks and annotations retain their normalised output positions; review their placement after changing framing.


### Undo History and Reset Changes

Batch Edit has visible **Undo History…** and **Reset Changes…** controls. The photo-edit timeline is shared by batch changes and individual editor tabs. Choose a history row to return to its state, then use later rows or Redo to move forward again. A new edit removes the redo branch. History holds up to 80 Undo steps for the current session; reopening a project starts history at its saved state. Imports, exports, collages and automation recipes have separate lifecycles and are not part of this timeline. Editor’s Edits menu and the Mac Edit menu also open history.

Reset Changes offers three explicit actions for workspace photos, including photos hidden by filters. Sources retained only for creations are excluded. **Restore Original Appearance** removes visual edits and restores native size while retaining encoding and metadata protection. **Reset Batch Settings** restores shared defaults (1600 × 1200 Fit, JPEG) while retaining individual overrides. **Remove Individual Overrides** makes photos inherit current batch settings; it does not restore originals. Each action supports Undo. Original files, collages, automation recipes and saved profiles remain intact. Checked export profiles still apply at export; inspect the output plan or choose Current edits separately. Reset selected edits removes only the selected photos’ overrides.


### Multiple collages and art collages

Use New Collage for a separate composition. Close a tab without deleting it; reopen it from Layout Gallery → Your Collages. Mac Command-W closes the current collage tab. Each composition keeps its own session Undo/Redo history, and projects save the compositions and open tabs.

Layout Gallery contains 74 arrangements with category/search controls. A card applies its layout to the current collage by default. Choose Create New Collage for a separate tab. Source and reference choosers show thumbnails.

Expand Art Collages for Shape, Text and Photomosaic. Shape/Text fill a silhouette with your chosen number of photo tiles, repeating selected photos when needed. All photo frames changes individual tile shapes; selected tiles have their own frame-shape control. Use HELLO or other short outline text to create photo-filled lettering. For a reference mosaic, import the reference, choose it visually, select candidate photos or Use entire workspace, and Generate. Colour/tone matching is approximate and depends on the photo palette. Disable reuse only when there are enough distinct usable photos. Generation shows progress and supports Cancel; Undo restores the previous arrangement. Up to 10,000 tiles are supported within output size limits. Very thin text may need fewer tiles. Only the active composition is exported as one PNG; originals are untouched.


### Direct crop boundaries and contextual tools

In Editor → Crop & Frame, drag the crop boundary’s corners or edges to select a freeform crop; drag inside to move it. Lock aspect ratio preserves the chosen proportions during boundary resizing. Keep export dimensions preserves the requested output size; otherwise width is retained and height follows the new aspect ratio. Changes commit as one Undo step when the gesture ends. The full transformed, adjusted source remains visible around the boundary. The source Crop view omits overlays. Choose Crop Options → Preview Edited Output to inspect masks, annotations, watermark and canvas treatment without leaving the crop tool. Numeric precision controls remain available. Batch Frame continues to move the photograph inside a fixed output frame.

Privacy and Annotate retain the open-photo strip (and sidebar on Mac/iPad) while editing a draft. Tab navigation is locked until Apply or Cancel, so changes cannot accidentally target a different document. Closing the draft does not close the photo tab.

Collages offers visible Photo Layout, Shape Collage, Text Collage and Photo Mosaic creation choices. Shape/text/mosaic choices open their setup controls directly. The layout gallery defaults to Apply to Current Collage when a composition is open; choose Create New Collage for a separate tab. Applying a layout supports Undo.


### Inspecting detail, tools and documents

Inspect Pixels renders full-resolution output for Fit, 100% and zoom/pan inspection. At 100%, one image pixel maps to one display pixel; this is separate from crop zoom and thumbnail size. Encoded Output Preview uses the same viewer, offers a profile selector and previous/next batch samples, and displays actual dimensions and byte count. Large full-resolution renders use more memory and may take time. On Mac, focus the photo and hold M to compare with the original.

On iPhone, Adjust, Crop and Retouch stay in the bottom tool strip; Tools contains Resize, Annotate, Privacy, Watermark and Export Settings. At accessibility text sizes, Tools and View menus preserve space for the photograph. Watermark editing provides direct move, resize and rotation controls for a single watermark; tiled patterns use inspector settings.

Mac photo tabs support drag ordering, Close Others and a searchable open-photo list. iPhone and iPad use a single-photo editor with Back to Workspace. Collage tabs also support ordering and Close Others. Closing tabs never deletes their sources or saved edits. Project names appear above the library and can be changed in Projects. Source storage accounting and Clear Imported Photos are in the separate Local Source Storage section.

### Fixed batch inputs and privacy coverage

Keep These Batch Inputs saves the current target IDs so filtering and gallery navigation do not change the job. Use Live Selection Instead returns to selection-based targeting. Individual Overrides filters photos with per-photo edits. Mixed width, height, fit mode and format are labelled; adjustment controls also indicate Mixed values. Use Current Edits Only clears checked export-profile selection without changing saved profiles or edits. Export plans show a resolved filename example; destination collisions receive numeric suffixes.

Changes to image geometry after masking flag Privacy Review and Needs Review. Review the final edited output and confirm mask coverage in Editor. The review state is saved in project instructions and cannot be cleared by accepting only framing. It is a reminder, not automatic validation of concealment or a guarantee that an image is safe. Review coverage separately for each export profile.

Quick Fix has progress/cancellation, preserves newer manual values if analysis finishes later and adds one Undo step for its whole batch. Cancelled analysis applies no automatic changes. Undo names the photo/operation where available; histories remain session-based.

### Current collage output

Composition previews identify pending or failed updates. Only an export matching the current composition inputs is offered as Current Export; changed compositions require another render. Previous output files are retained. In Freeform, Move Frames edits frame position/size/rotation, while Reframe Photos moves the photo inside its frame. Handles, snapping, layer order and numeric controls are available. Replace Photograph opens thumbnails; drag a photo from a chooser onto a tile to replace it, or use the selected tile’s Drag to Swap label to exchange photos and framing. Captions remain attached to their frames.

Layout cards preview up to 24 chosen photos, with recommended/category/orientation filters. Saved collages show actual composition previews outside Private Editing Mode. A reference mosaic’s setup separates reference choice, tile photos and requested detail; matching quality still depends on the photo palette. Text art supports selected outline fonts and multiple lines. Existing projects keep their prior text geometry until regenerated.

Automations separates Workflows, Pending Reviews and Failed Jobs. Input, output and publication mode remain visible. Test previews do not publish; required review must be approved explicitly before export.

Collage mask review is independent of source-photo review: changing a cell/layout can expose a detail even when the source photo’s mask was previously checked. Inspect and confirm the final composition separately. The reminder does not prevent you from exporting; you remain responsible for checking final coverage.

Collage output offers the native formats available on this system, quality controls and an encoded preview. Non-transparent formats use a white background. After review, Export Reviewed Files copies approved encoded files to a selected folder without recompression; collisions receive safe suffixes. Completed copies remain available if a later copy fails or is cancelled.

## Workspace and GIF Creator

Workspace holds the photos you bring to a task. Filters never clear selections: the summary includes selected photos hidden by filters. Use Actions to edit, convert, make a collage, create a GIF or export explicit inputs. Right-clicking an unselected photo targets that photo; a selected photo exposes labelled group actions. Removing a workspace photo leaves the original file unchanged and retains the source while a current or saved creation uses it.

Open Create GIF and Select Photos, or select workspace photos and choose Actions → Create GIF. Cancel restores your previous selection and filters. Frames start in selection order; range selections use workspace order. Drag frames or use Frame → Move Earlier/Later; duplicate, remove or replace them from that menu. Order sorts only when you request it. Add Photos uses the same workspace picker.

Timing can apply to this frame, selected frames or every frame. Timing uses 0.01-second units, with a 0.1-second minimum. Choose Fit or Fill, canvas dimensions, a background and optional per-frame crop. Source edits, including privacy masks, are rendered before GIF fitting/cropping so they stay attached to the picture. Add captions, arrows, rectangles, ellipses or speech bubbles; move and resize selected annotations directly. This Frame affects one frame, Until Removed includes following frames and later additions until ended, and All Frames includes every frame. End Before This Frame ends a range. Explicit ranges follow their frames when reordered.

GIF instructions save automatically with the workspace. More → Save Workspace Copy preserves a separate recovery copy. Starting another GIF retains the previous one under More → Saved GIFs. GIF Undo/Redo is separate from photo editing. Missing photos can be replaced from Frame → Replace Photo, or located through Projects → Relink when their workspace reference remains.

Export uses native GIF encoding. Small File, Balanced and Best Quality change dimensions; you can enter custom dimensions afterwards. Photographic GIFs have a limited palette and can show banding. File size is reported after export. Review every encoded frame before sharing. iPhone/iPad use the native sharing and reviewed Files destination flow. GIFs do not use the optional still-image sensitive-content checker.

GIF previews use temporary downsampled files, removed when the editor closes or enters the background. Unexpected termination may leave temporary files for system cleanup. Private Editing Mode disables the GIF source thumbnail memory cache too; it is not encryption or secure deletion.


## Source ownership, recovery and conversion

Remove from Workspace hides a photo from ordinary workspace actions. GIFs, collages and their session Undo/Redo keep the same source record and working copy while needed. Saving and reopening preserves this ownership and membership. Free Unused Working Copies removes only unreferenced owned copies after checking current instructions, saved project copies and watermark references. Clear Workspace & Creations is a separate confirmed operation that discards current photo edits and creations; save a workspace copy first if they are needed.

Relink keeps the source UUID and editing instructions but replaces its managed pixels. Review the affected photo and every current or saved GIF/collage. GIF flags include masks captured when a frame was added, even if the workspace photo no longer has masks. Framing and protective coverage require explicit review. Old exported files remain unchanged; current sharing approval is revoked. Missing GIF preview errors identify the failed frame, with Replace Photo and Locate Missing Photo actions. Saved GIFs remain available from the empty creator as well as More.

Convert is available from Workspace Actions, Mac/iPad Quick Tasks and the iPhone home. It captures explicit inputs and uses source dimensions by default, retaining visual edits and crop geometry. Also Resize enables deliberate resizing. Existing projects and presets retain their saved output sizing. Existing explicit export profiles use their own sizes. Editor photos inherit batch defaults except for individual field overrides; edits in Editor target that photo only. Tool-first Edit, Batch, Convert, Resize and Collage selection uses the same workspace. Convert and Resize are available from Quick Tasks and the iPhone Home screen; Privacy is an Editor tool. Adding photos to an existing collage preserves its current cells and settings.

Project instructions reference local working copies and are not self-contained cross-device projects. To move work between devices, source files must be transferred and relinked separately. Sensitive-content checking requires the appropriate signing capability and system policy; manual review remains available. GIF review is always manual. GIF presets primarily change dimensions, not a photographic-quality guarantee. Explicit Mac browser-image drops may download an HTTPS image from its website; image processing remains local. Physical-device performance, Pencil/trackpad and complete VoiceOver accessibility still require appropriate verification.

On iPad, landscape Editor places a narrow toolbox at the right edge with settings beside it. In portrait or narrow windows, tool settings open from the selected tool or its adjacent Options button. Collapse the landscape settings panel for more canvas space; tap the selected tool to reopen it.

### Retouch: Heal and Clone

Open a photo in Editor and choose Retouch (the bandage icon). Heal samples nearby texture and adapts its broad colour and lighting to the destination. Paint over a small blemish, or use Set Source to choose the texture yourself. Clone copies a source you choose: tap Set Source, tap clean photo detail, then paint over the destination. On Mac, Option-click also sets the source.

Size, hardness and opacity control the brush. Aligned Source keeps the offset between source and destination across strokes; switch it off to start each stroke from the same source. Source Position provides numeric sampling coordinates. The source indicator shows where sampling occurs. iPhone keeps the canvas visible and opens detailed controls from Brush; iPad uses the adjacent inspector or an anchored Options popover.

Undo/Redo works per stroke and the stroke list can remove individual strokes. Apply commits the draft; Cancel discards that session's changes. Retouch instructions are saved with the photo and retained in GIF frame snapshots. They are omitted from reusable batch presets. Originals remain untouched, and cloning from a privacy-masked source samples its concealed appearance.

Healing is local texture correction, not generative object removal. Texture boundaries and large removals may need a manually chosen source or several smaller strokes. Retouch coordinates belong to the finished photo: check or redo strokes after changing the crop, rotation or canvas. Strokes are limited to 200 per photo and 2,000 recorded points per stroke. Pencil pressure sensitivity and physical-device performance have not been verified.


### Editor layout and tool options

Workspace navigation starts collapsed while editing on Mac and iPad. Use the sidebar button to show it; a deliberate choice lasts for the current window. Drawing drafts temporarily hide navigation, and accessibility text sizes on iPad use a single-column workspace. Photo tabs, batch inputs and creation frames remain separate.

Undo and Redo are visible in the photo header. They use the active photo, draft or creation history. Edits contains copy/paste, detailed history and Restore Original; on iPhone these actions are in the photo-name menu. On iPhone, Adjust, Crop and Retouch are directly available; Tools includes Resize, Privacy, Annotate, Watermark and Output. Privacy and annotation drafts use a fitted canvas with the same toolbox and explicit Apply/Cancel controls. Apply or discard changed drafts before switching to ordinary editing tools.

On wide screens, options sit beside the toolbox. Portrait iPad options are anchored to the selected tool; more detailed properties can scroll. On iPhone, Options opens a readable sheet while keeping the underlying draft. View zoom is independent of cropping: drawing tools show a multiplier relative to Fit, not actual pixel magnification. Use Inspect actual pixels in ordinary editing for full-resolution inspection.

Batch headers show the operation count. Open the photo-count menu for fixed-input details and Change Photos. Workspace selection and its hidden count are shown separately. Compact stack badges mark operation membership independently of checkmarked selection. Gallery actions → View → Show operation photos only changes the view, not membership or selection. Thumbnail size and filename controls are in View. GIFs keep frame duration near the strip; Options opens Timing, Canvas or Text. On iPhone, collage Canvas/Photo/Output controls open their properties directly; the actions menu contains Open Collages.


### Workspace controls and properties

On iPhone, View and gallery options → View contains Browse, Frame and Compare. Batch Settings opens the batch properties; the focused-photo menu in gallery options offers Rotate and Refine for that photo only. On portrait or narrow iPad, the editing-settings toolbar button opens a sheet instead of reserving a gallery column. Landscape iPad keeps adjacent properties when enough width is available.

Batch Resize & Canvas uses compact fields and disclosures for Framing, Rotate & Flip and canvas appearance. Format and Export settings remain available. Mixed-value details explain sparse edits; changing one field preserves other photo-specific edits. Gallery View offers filename and favourite-button visibility. Favourite photos retain their heart; every photo can be favourited through its context menu or accessibility action. Presets and Help & Review are collapsible sidebar sections.


### Focused adjustments

Adjust groups existing controls into Light and Colour. Open either heading to show or hide its controls. On iPhone at standard text sizes, the inline Adjust panel displays one chosen parameter: tap its name for the other adjustments, edit its value or slider, or reset that parameter. All adjustment controls opens the complete inspector. Larger text uses the complete inspector. Choosing a parameter or collapsing a group does not change edits, batch inputs or Workspace selection.

On iPhone the gallery’s ellipsis menu combines photo actions and view options; Select remains visible. On larger screens Actions and View options remain separate. The operation’s photo-count menu identifies its scope and provides explicit input changes; selection checkmarks and the selected/hidden count remain independent.
