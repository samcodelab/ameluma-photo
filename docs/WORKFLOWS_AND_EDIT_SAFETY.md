# Workflows and edit safety

Framepebble has one source library and shared editing state, with four separate workflows. Batch Edit edits the explicitly labelled all-photo, selected-photo or filtered-result inputs. Editor edits and exports the visible active photo, with one current-edits rendition regardless of checked batch profiles. Collages select their own sources and export one composition. Mac Automations retain independent authorised inputs, action configuration, outputs and review queues. Switching workflows does not recreate sources or reset edits.

## Scoped changes and inheritance

ConfigurationField identifies scalar settings and deliberate edit groups. Inspector bindings specify exactly which fields they change, including exposure independently of other adjustments. Multi-photo updates apply those fields to each target's own effective configuration. Masks, annotations, dimensions and crop geometry survive unrelated changes. Mixed fields are listed; numeric controls use the first target as a representative until changed. An explicit field assignment also works when the chosen value already matches that representative.

ImageOverride stores a ConfigurationPatch with only scoped fields serialized. Unlisted settings inherit EditingSnapshot.settings. Crop geometry and individual dimension rules remain normalized and independent of preview size. Individual rotation does not freeze format, quality or size. The inspector lists overridden categories for the active photo and offers category-specific reset to batch inheritance. Resetting framing preserves unrelated authored edits. Resetting all overrides returns to batch settings rather than an unedited original if the batch itself has edits.

Project schema 4 accepts versions 2 and 3. Migration compares each legacy configuration with its saved batch settings, preserves all effective differences and explicit dimension rules, and retains the same effective output. It cannot reconstruct whether a historical difference was intentional; preserved legacy differences remain overrides until explicitly reset. Schema-4 files are not supported by older application builds. Original files and source UUIDs are preserved; watermark snapshot references in patches are rebased when containers move.

## Active photo and batch inputs

activePhotoID is separate from the selected-ID set. The active photo has a strong outline and active indicator; selected group members have selection outlines/checkmarks. Plain-clicking an already selected group member changes the active photo while preserving the explicit batch; clicking an unselected photo selects it alone. Mac Command-click toggles membership, Shift-click selects a range from the last clicked anchor, and Command-Shift-click extends a range. Command-A selects visible photos while the gallery has keyboard focus. Arrow navigation moves the active photo without changing the group. Filtering intersects the selected set with visible results and selects the first visible active photo when the previous active photo disappears. Library filters update gallery selection. Explicitly open editor tabs are independent of those filters, and export/share always names the active tab’s photo.

All images is an explicit whole-library batch scope even when a filter is shown. Selected images uses visible selected IDs; Search results uses the visible filtered results. The displayed target count and export plan distinguish these operations. Right-click actions explicitly target the clicked photo; group paste is separately labelled. Copy Chosen Edits copies checked categories, and Paste replaces only those categories. Privacy and annotations are never included implicitly.

## Framing and previews

Per-photo precision and context-menu Smart/Keep Subjects pass explicit IDs. They do not mutate batch scope. Commands that replace manual framing are labelled accordingly. Normal batch automatic framing retains manual exceptions.

Browse is labelled Originals; Frame and Editor show processed results. Framing gestures request reduced-resolution rendering through the same composition pipeline, retaining adjustments, watermarks, masks, annotations, colour/background and canvas styling. When the rendered preview is behind the latest geometry, it says Updating processed preview. The final settled preview uses a larger resolution. Rendering can lag on expensive effects; no full-resolution gesture export is performed.

Export-plan previews use the actual planned profile configuration and an input photo from that plan. Encoded Output Preview renders at final resolution, uses the same encoder and bounded target-size search as export, then decodes the encoded bytes. It reports exact dimensions and byte count, without publishing a file. It can take time and memory for large output sizes; unachievable compression targets fail visibly. Normal editing previews are reduced-resolution compositions, not compression proofs.

## Export and sharing

Plans show input count, output count and active profile count, for example 5 photos → 15 files · 3 profiles. Each profile lists format, requested size, naming template and destination. Running export counts and profile details are frozen from the submitted requests, so switching sections cannot change the displayed operation. Current edits is the default when no profiles are checked. New export presets omit photo-specific masks and annotations; transfer those only through explicitly chosen edit categories. Existing saved profiles retain their data. Selected profiles control variant dimensions/encoding while preserving authored orientation, adjustments, protection and individual framing. Exact preserve-aspect output sizes depend on source geometry and are shown by encoded preview. Explicit profile destinations are honoured; multiple profiles without explicit destinations get named subfolders.

Editor export/share is one current photo and one rendition. Batch export/share uses its labelled inputs and profiles. Export & Share This Photo from a context menu uses only the clicked photo's current edits, independently of batch profiles. Collage render/share uses only its newly validated composition.

ShareOutputSession is an immutable set of successful URLs from one operation, with that operation's result summary. It never reads accumulated completedOutputs. Partial failures report the number failed and offer only successes. Total failure and cancellation do not automatically open a share session. Completed files remain in export history for explicit review or retry. Per-file history review contains that file only; collage-history review is explicitly labelled. No system handoff happens until the user approves outputs and selects the native sharing/save action.

## Validation and limits

Regression tests cover multi-photo field preservation, mixed assignments, inheritance, migration/roundtrip, selected edit categories, active/group selection and filters, section changes, explicit framing IDs, multiple profiles, partial/total sharing failures, and encoded/export pixel/dimension consistency across orientation, cropping, canvas and masks. Mac platform tests cover original preservation, automation stability/review/retry and browser imports.

Actual Mac UI review uses synthetic fixtures and an isolated project/automation store. Physical iPhone/iPad touch, VoiceOver and large-batch performance still need validation. Selection and workflow navigation state are session UI state; this change does not persist that navigation state in project files. Sensitive Content Analysis remains gated by signing capability and Apple system policy. No new dependency, telemetry, upload service or source-file modification is introduced.

## Library-first navigation

Photo Library appears above Workflows. All Images and the other library categories always open a full-width browsing gallery, clearing the precision inspector. All Images clears a previous content search. The library is a navigation destination, not another processing workflow: it has no implicit export targets. It retains edits, current composition and the explicit batch scope. Double-click on Mac (double-tap on iPad, tap outside selection mode on iPhone) opens Editor. Context menus expose Open in Editor and Privacy for the clicked photo. Gallery returns from Editor; Batch Edit Selected explicitly carries the selected IDs into Batch Edit. Returning to the batch restores its gallery mode. Projects and clear-library actions live at the top of the library sidebar.

Editor now has explicit tools above one main canvas. The central surface permits crop gestures only with Crop & Frame active; switching to another inspector stops framing without changing configuration or batch scope. Mac/wide iPad precision controls omit the duplicate preview. Compact framing retains its dedicated preview. Annotate and Privacy set the requested starting tool before opening the same reversible overlay editor. The processed filmstrip follows active-photo changes, with animation disabled for Reduce Motion.

Async preview requests capture their requested configuration before awaiting processing. Displayed source/processed images are tied to the requested source identity; switching photos shows loading until that photo’s image is ready, rather than displaying the previous photo under a new name. Original comparison also requires the matching source-representation key. This change does not affect export rendering or source data.


### Editor tabs and privacy tools

Double-click a library photo (tap on iPhone) to open it in Editor. Reopening the same photo activates its existing tab. Tabs retain their own tool context while the app is running. Close a tab to close its view; its edits remain in the project, and original files are never deleted. Closing the last tab returns to the library. Mac Command-W closes the current photo tab. Open-photo IDs and the active tab are saved with the project; older projects open normally with no tabs. Tool context starts with Adjust after reopening a saved project.

Privacy Review remains a gallery filter, not a separate editing workflow. Right-click/long-press **Edit with Privacy Tool** opens that photo’s editor tab with Privacy active. Apply or Cancel the privacy/annotation draft before changing tabs. Batch selection and export scope are not changed by opening or closing a photo tab. Library filtering still removes hidden photos from the explicit selected group.


Restore Original in Editor writes explicit neutral appearance overrides for the active photo, using Preserve Aspect Ratio at 100% for native dimensions. It intentionally overrides inherited visual batch changes while retaining export/compression/metadata fields and privacy-export protection. It removes crop dimension derivation and authored masks/annotations, commits one Undo step, and leaves other sources, batch settings and files unchanged. Confirmation is required; the Original preview toggle remains comparison only.


### Expand a crop back to the full image

In Crop & Frame, choose **Reset Crop · Full Image** (also available as **Original · Full Image** in Output aspect ratio). This reveals the complete source at native dimensions while retaining rotation, adjustments, watermarks, masks, annotations and export settings. Undo restores the previous crop. **Use Batch Framing** instead returns to inherited batch framing; **Restore Original** removes all visual edits. Crops never discard the source pixels. Masks and annotations retain their normalised output positions; review their placement after changing framing.


### Undo History and Reset All Changes

Batch Edit has visible **Undo History…** and **Reset All Changes…** controls. The photo-edit timeline is shared by batch changes and individual editor tabs. Choose a history row to return to its state, then use later rows or Redo to move forward again. A new edit removes the redo branch. History holds up to 80 Undo steps for the current session; reopening a project starts history at its saved state. Imports, exports, collages and automation recipes have separate lifecycles and are not part of this timeline. Editor’s Edits menu and the Mac Edit menu also open history.

Reset All Changes confirms that it affects every imported photo, including hidden photos and individual editor-tab overrides. It restores initial batch defaults (1600×1200 Fit, JPEG) and clears individual processing edits, including masks/annotations/watermarks. It is a single Undo step. Photos, original files, favourite flags, saved profiles, compositions, recipes and completed exports remain intact. Checked export profiles remain selected and still apply on export; reset those selections separately when needed. Reset selected edits only removes the selected photos’ overrides and returns them to the current batch defaults.
