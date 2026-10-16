# Using Ameluma Photo

Import photos/files or a folder. The app makes local source copies and begins on-device classification. Existing editing settings remain in place when adding images.

Use the search field for recognized label words such as dog or beach; suggestions show labels actually found. Combine words only when both labels are present. Search is not arbitrary language understanding. In Batch Edit, choose the labelled inputs: all images, selected images or search results. Editor always acts on its visible current photo. Select visible results from the More menu to edit/export only matches.

Browse navigates originals. Frame shows output-shaped thumbnails; drag within an image to reposition it. Pinch or hold Option while scrolling to zoom. Normal Mac scrolling navigates the grid. On touch devices, Frame is a deliberate manipulation mode; switch to Browse for easy scrolling. Double-click on Mac or use Refine to open larger precision controls. The same position/zoom state appears in both surfaces. Before/after and guides help judge the result.

Choose a size preset or enter pixels. Fit keeps the full image with padding; Fill crops to fill the output; Stretch distorts; Canvas adds alignment/background options; Preserve Aspect Ratio calculates the other dimension from the chosen basis. Crop presets change output dimensions. Prevention of upscaling can leave padding. Rotation/straightening can expose background or change subject placement, so review affected images.

Smart and Keep Subjects use native spatial detections/saliency. Batch automatic actions keep manual overrides. Per-image Smart/Keep Subjects intentionally replaces that image's manual crop. Review the Needs Review category and use Previous/Next to inspect it. Accept a proposal, refine manually, or reset/centre it. Vision can be wrong even when no review flag appears.

Enable a text/image watermark and configure its relative size, opacity and anchor. Logos are copied locally. Watermark presets and full export presets are saved locally. Processed previews retain watermarks and other treatments while framing; Updating processed preview identifies a render still catching up. JPEG/HEIC flatten transparency; use PNG/TIFF when alpha is needed.

Choose quality or a target KB limit. The encoder searches within a minimum-quality floor and fails if the requested size is infeasible. Reduce output dimensions or raise the limit rather than expecting arbitrary images to fit any size.

Leave export-profile checkboxes empty to export current settings. Select multiple profiles to create separate folders. Manual image framing continues to apply. Naming tokens are {name}, {suffix}, {id}. Original/existing files are retained and collision names are numbered. Export shows progress, supports cancellation and reports individual errors. Retry unfinished requests after selecting a destination. Completed results can be shared. iOS Photos additions require the system permission and depend on format support.

The local session restores sources, edits, analysis and pending work after relaunch. Re-select an external destination when retrying after relaunch. Originals remain unchanged. Keep important output files in a permanent Files/Finder destination; the local session is not a backup or cloud service.

## Everyday tools

Choose Batch Edit, Editor or Collages on iPhone/iPad; Mac also offers Automations. These share the same library and preserve edits when switching. Import images if needed. More Tools opens contextual Frame, Adjust, Create and Export controls. Rotate acts on the selected photograph; use Refine for position/zoom/crop or Compare for original/processed output.

Adjust sliders show neutral values and individual resets. Quick Fix applies conservative automatic suggestions; no change can be appropriate. Always preview coloured scenes before accepting a colour correction. Undo restores the earlier settings.

## Collages and overlays

Use Collages and Choose Source Photos independently of batch inputs, choose a quick layout or open the 74-layout gallery, select a cell and drag its photograph. Zoom/position controls provide alternatives. Change its source or swap with the next cell; freeform adds placement/rotation. Add titles/captions, spacing/background/borders/corners/shadows, then render and review/share. The project remains editable.

Privacy Review is a library filter for flagged photos. Privacy is a tool inside Editor. Right-click (or long-press) a photo and choose Edit with Privacy Tool; flagged photos use Reveal & Edit with Privacy Tool. If nothing is flagged, show All Photos and flag or edit a photo from its context menu. Automatic findings require Apple’s capability and system settings; manual flags remain available.

Privacy editing uses the main Mac/iPad workspace and a full-screen iPhone editor. The editor keeps a draft until Apply. Drawing selects the new area immediately; click empty photo space to return to Draw. Select chooses existing areas; drag their bodies to move them or their eight handles to resize. Change the selected effect or use the numbered area controls. Undo, Redo and Delete stay above the preview. Cancel, Escape and Close Editor discard all changes made during this editing session, preserving any previously applied masks. Apply commits the draft as one project Undo step. Apply & Crop explicitly applies the draft before opening precision cropping. Freehand draws a path; annotations support basic fonts/alignment/colour. Inspect the final output before sharing.

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

Browse shows originals; Frame shows the intended output; Compare shows before and after. Select switches editing/export scope to selected photos. Done keeps that scope—check Apply to before export. On iPhone, open Refine for touch cropping. On iPad, Frame → Reframe thumbnails deliberately enables dragging/pinching the selected photo; Done Reframing returns to normal gallery scrolling. The inspector adapts to available space. Search categories come from Vision and can be wrong or incomplete.

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

Choose **Workspace** in Workspace to see the full gallery. On Mac, double-click a photo to open Editor; on iPhone tap it outside selection mode. Right-click or long-press for **Open in Editor** or **Edit with Privacy Tool**. Use **Gallery** to return. Select multiple photos and choose **Batch Edit Selected** for a batch. Browsing does not reset edits, and the library’s project/clear actions never delete original files.

### Editor tools

Use **Adjust**, **Crop & Frame**, **Resize**, **Annotate**, **Privacy**, or **Watermark & Format** above the photo. The photo moves only while Crop & Frame is active, so adjusting lighting cannot accidentally change framing. On Mac and wide iPad, framing controls act on the large main preview. Original is a comparison view; choosing Crop & Frame returns to the processed result. Open photos appear in closable editor tabs on Mac and iPad. On iPhone, use Open Photos to switch or close the current photo. Numeric crop positions use percentages. Batch inheritance and category reset controls are available under the defaults/overrides disclosure.

### Larger text on iPhone

With accessibility text sizes, Editor separates the filename and navigation controls, and offers all editing tools through **Tools**. Adjustment values move onto their own full-width row. Gallery controls stack vertically, keeping the photo and selection actions readable. Use the compare button’s VoiceOver label to switch between the original and edited view.

When the editing toolbar cannot fit, use **More** for the remaining tools. At accessibility text sizes, use **Tools**. The gallery’s action menu also contains photo editing, privacy, preview size and Undo/Redo controls when larger text makes separate rows impractical. **Use Batch Framing** removes only the current photo’s framing override.


### Editor tabs and privacy tools

Double-click a library photo (tap on iPhone) to open it in Editor. Reopening the same photo activates its existing tab. Tabs retain their own tool context while the app is running. Close a tab to close its view; its edits remain in the project, and original files are never deleted. Closing the last tab returns to the library. Mac Command-W closes the current photo tab. Open-photo IDs and the active tab are saved with the project; older projects open normally with no tabs. Tool context starts with Adjust after reopening a saved project.

Privacy Review remains a gallery filter, not a separate editing workflow. Right-click/long-press **Edit with Privacy Tool** opens that photo’s editor tab with Privacy active. Apply or Cancel the privacy/annotation draft before changing tabs. Batch selection and export scope are not changed by opening or closing a photo tab. Workspace filtering retains hidden selections; the summary reports their count.


### Restore an original photo

In Editor, choose **Restore Original…** below the preview (on iPhone or in a narrow window, open **Edits**). Confirm to restore the active photo’s uncropped, unrotated appearance and native dimensions, removing lighting/colour adjustments, canvas effects, watermarks, annotations and privacy masks. Other photos and batch defaults remain unchanged. Export format, compression and metadata protection remain as configured. The Original comparison toggle only previews the source; Restore Original changes the editing instructions. Undo brings back the previous edits. Neither action modifies the original file.


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

On iPhone, Adjust, Crop and Privacy stay in the bottom tool strip; Tools contains Resize, Annotate, Watermark and Export Settings. At accessibility text sizes, Tools and View menus preserve space for the photograph. Watermark editing provides direct move, resize and rotation controls for a single watermark; tiled patterns use inspector settings.

Photo tabs have thumbnails, drag ordering, Close Others and a searchable open-photo list. Collage tabs also support ordering and Close Others. Closing tabs never deletes their sources or saved edits. Project names appear above the library and can be changed in Projects. Source storage accounting and Clear Imported Photos are in the separate Local Source Storage section.

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

Convert is available from Workspace Actions, Mac/iPad Quick Tasks and the iPhone home. It captures explicit inputs and uses source dimensions by default, retaining visual edits and crop geometry. Also Resize enables deliberate resizing. Existing projects and presets retain their saved output sizing. Existing explicit export profiles use their own sizes. Editor photos inherit batch defaults except for individual field overrides; edits in Editor target that photo only. Tool-first Edit, Batch, Convert, Censor and Collage selection uses the same workspace. Adding photos to an existing collage preserves its current cells and settings.

Project instructions reference local working copies and are not self-contained cross-device projects. To move work between devices, source files must be transferred and relinked separately. Sensitive-content checking requires the appropriate signing capability and system policy; manual review remains available. GIF review is always manual. GIF presets primarily change dimensions, not a photographic-quality guarantee. Explicit Mac browser-image drops may download an HTTPS image from its website; image processing remains local. Physical-device performance, Pencil/trackpad and complete VoiceOver accessibility still require appropriate verification.
