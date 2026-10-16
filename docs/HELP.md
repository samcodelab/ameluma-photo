# Using Ameluma Photo

Import photos/files or a folder. The app makes local source copies and begins on-device classification. Existing editing settings remain in place when adding images.

Use the search field for recognized label words such as dog or beach; suggestions show labels actually found. Combine words only when both labels are present. Search is not arbitrary language understanding. Choose **Apply to** carefully: all images, selected images, search results or current image. Select visible results from the More menu to edit/export only matches.

Browse navigates originals. Frame shows output-shaped thumbnails; drag within an image to reposition it. Pinch or hold Option while scrolling to zoom. Normal Mac scrolling navigates the grid. On touch devices, Frame is a deliberate manipulation mode; switch to Browse for easy scrolling. Double-click on Mac or use Refine to open larger precision controls. The same position/zoom state appears in both surfaces. Before/after and guides help judge the result.

Choose a size preset or enter pixels. Fit keeps the full image with padding; Fill crops to fill the output; Stretch distorts; Canvas adds alignment/background options; Preserve Aspect Ratio calculates the other dimension from the chosen basis. Crop presets change output dimensions. Prevention of upscaling can leave padding. Rotation/straightening can expose background or change subject placement, so review affected images.

Smart and Keep Subjects use native spatial detections/saliency. Batch automatic actions keep manual overrides. Per-image Smart/Keep Subjects intentionally replaces that image's manual crop. Review the Needs Review category and use Previous/Next to inspect it. Accept a proposal, refine manually, or reset/centre it. Vision can be wrong even when no review flag appears.

Enable a text/image watermark and configure its relative size, opacity and anchor. Logos are copied locally. Watermark presets and full export presets are saved locally. Watermarks appear in composited previews after a framing gesture completes. JPEG/HEIC flatten transparency; use PNG/TIFF when alpha is needed.

Choose quality or a target KB limit. The encoder searches within a minimum-quality floor and fails if the requested size is infeasible. Reduce output dimensions or raise the limit rather than expecting arbitrary images to fit any size.

Leave export-profile checkboxes empty to export current settings. Select multiple profiles to create separate folders. Manual image framing continues to apply. Naming tokens are {name}, {suffix}, {id}. Original/existing files are retained and collision names are numbered. Export shows progress, supports cancellation and reports individual errors. Retry unfinished requests after selecting a destination. Completed results can be shared. iOS Photos additions require the system permission and depend on format support.

The local session restores sources, edits, analysis and pending work after relaunch. Re-select an external destination when retrying after relaunch. Originals remain unchanged. Keep important output files in a permanent Files/Finder destination; the local session is not a backup or cloud service.

## Everyday tools

On iPhone, choose Resize or Convert, Perfect a Photo, Make a Collage, Hide Something or Prepare to Share. Import images if needed. More Tools opens contextual Frame, Adjust, Create and Export controls. Rotate acts on the selected photograph; use Refine for position/zoom/crop or Compare for original/processed output.

Adjust sliders show neutral values and individual resets. Quick Fix applies conservative automatic suggestions; no change can be appropriate. Always preview coloured scenes before accepting a colour correction. Undo restores the earlier settings.

## Collages and overlays

Create a collage from the active scope, choose one of three layouts, select a cell and drag its photograph. Zoom/position controls provide alternatives. Change its source or swap with the next cell; freeform adds placement/rotation. Add titles/captions, spacing/background/borders/corners/shadows, then render and review/share. The project remains editable.

In Hide Something/Annotate, drag to create a region or use Add centred area. Choose a shape/effect, select an existing region to move it, or adjust its controls. Freehand draws a path. Text supports basic fonts/alignment/colour. Crop to Hide opens precision reframing: manually move the crop to exclude unwanted details, then check the final output.

Opaque covers and cropping offer stronger concealment than blur/pixelation. Masked exports flatten the pixels and omit copied source metadata. Do not share editable project instructions when you intend to share only a concealed image.

## Review, projects and private editing

Prepare to Share renders final outputs into local Exports. Review concealed previews, exclude unwanted files, approve the selection, then share/copy/save reviewed images. Changing inclusion requires new approval. Automatic sensitive-content detection is not provided. Approval is your decision, not a safety certification.

Projects saves a local copy of source references and editing instructions. New project preserves the previous workspace first. Open a recent or selected JSON project; relink a missing selected source to the corresponding original. Cross-device project files may need relinking. Sources are never automatically deleted.

Private mode bypasses memory thumbnail caching. Conceal covers the workspace; iOS also conceals when backgrounded. Saved originals/edits/exports remain for recovery; no secure deletion/encrypted vault is promised.

## Mac folder workflows

Open Automations, create a recipe, choose separate authorised input/output folders, configure Studio settings/action toggles and choose Automatic or Review Before Export. Privacy review always requires manual approval in this build. Enable monitoring and add an image. Transfers must stabilize and decode before processing. Run Now reconciles; Test previews a sample without writing the destination. Pause finishes the current native operation before stopping new images.

The menu bar remains available with Studio closed. Quit stops monitoring. Missing/replaced/revoked folders may require selecting them again. Correct a failed input or destination, then retry. Inputs/outputs cannot overlap or feed another workflow. No login item or background daemon is installed.

## Browser images and network folders on Mac

Drag the image itself from a browser. Framepebble uses supplied image bytes first, or downloads an explicitly dropped HTTPS image address without browser cookies or saved credentials. Browser downloads are limited to 25 MB. Login-protected, HTTP-only or page links may need to be saved in the browser first.

File/folder imports show copy progress below the grid. Completed images appear incrementally; you can scroll, crop and reframe them while the remaining files copy. Folder totals are discovered as the import runs. Cancel retains completed images. A stalled NAS read may take time to respond to cancellation. Vision search indexing starts after acquisition finishes.


For the current workflow, ownership, conversion and recovery behaviour, use the bundled [Help](../Resources/Legal/Help.md), which is the authoritative end-user guide. Workspace filtering preserves hidden selections. Sources required by GIFs and collages remain owned by the project after workspace removal. Project instructions are local references, not self-contained cross-device files. Current verification is in [the reliability review](RELIABILITY_REVIEW.md); older audits and screenshots are historical evidence only.
