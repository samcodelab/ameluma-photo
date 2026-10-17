# iPad contextual tools — 16 October 2026

## Review

The previous implementation's centred sheet was the wrong presentation for contextual editing options: it obscured the photo and disconnected settings from the control that opened them. The prior iPad layout report describes that superseded design.

Representative first-party references checked during this change (not an exhaustive survey or hands-on test of installed competitor apps):

| Editor | Documented pattern | Application to Ameluma |
| --- | --- | --- |
| [Photoshop on iPad](https://helpx.adobe.com/photoshop/ipad/get-started/overview-and-setup/workspace-ipad.html) | Tool-triggered contextual options, with movable/dockable options. The official workspace illustration shows options beside the toolbar. | Keep tool settings beside or below their tool, rather than in a detached modal. |
| [Affinity Photo 2 iPad](https://affinity.help/photo2ipad/en-US.lproj/pages/Workspace/contextBar.html) | A context toolbar updates for the selected tool and can scroll when needed. | A compact context row immediately below the shared toolbox. |
| [Procreate](https://help.procreate.com/procreate/handbook/interface-gestures/interface) | Canvas-first interface with tool buttons and frequent controls at the edges. Official interface illustration inspected. | Preserve a clear canvas; avoid persistent instruction blocks and disabled document tabs. |
| [Lightroom mobile](https://helpx.adobe.com/lightroom/mobile/get-started/workspace-overview.html) | Editing tools such as Crop, Edit, Masking and Remove share the editing toolbar. | Privacy belongs with the other photo tools. |
| [Photomator](https://support.pixelmator.com/photomator-user-guide/color-adjustments/white-balance) | Toolbar entry to adjustments and contextual adjustment controls. | Keep options tied to the selected editing task. |
| [Pixelmator Pro iPad](https://support.apple.com/en-nz/guide/pixelmator-pro-ipad/pixbb01478cd/ipados) | A common document toolbar, with tool shortcuts and contextual sidebars. | Reuse the existing editor and explicit photo target. |

The architecture and processing capabilities of these applications are not being copied. No competitor images or artwork are shipped with Ameluma.

## Implemented

- The embedded iPad overlay editor identifies itself as Editor and uses the same PhotoEditorTools component as ordinary editing. Adjust, Crop, Resize, Annotate, Privacy, Watermark and Export Settings remain in the toolbox.
- Privacy/annotation interaction mode, effect/type and shape appear directly underneath that toolbox. Detailed controls and object selection open from Options in an anchored popover, with compact adaptation explicitly preserving the popover.
- Removed the detached sheet, overlay-only iPad rail and permanent iPad side inspector. Removed inactive document tabs during drafts, keeping the filename in the canvas status bar; changing photos remains blocked until the draft is resolved.
- Privacy and Annotate share the existing overlay session, configuration and history. No additional editing engine, source registry, persistent model or selection system was added.
- Leaving a changed draft for a different tool requires explicit Apply or Discard. A failed concurrent-edit validation leaves the draft intact. Batch inputs and the active photo stay unchanged. Existing Apply and Cancel actions remain.
- Mac retains its established inspector presentation, with an anchored fallback for narrower windows. iPhone retains its current overlay presentation and uses the shared tool routing.

## Regression coverage

Added state tests for Privacy ↔ Annotate preserving the same draft/history, explicit draft resolution on tool changes, per-photo scope, batch membership preservation, discard behavior and rejection of stale drafts after concurrent edits. Native full-shell iPad captures cover portrait, selected masks and landscape.

The synthetic photo visibility assertion now recognizes both the sky and hillside colors. The old sky-only measurement undercounted photographs with an opaque mask over the sky. This assertion is a coarse visibility check; visual captures and interactive verification are still required.

## Verification results

- Full iPad Simulator suite: **205 tests, one Photos permission integration skip, zero failures** (`/tmp/ameluma-toolbox-ipad-complete.log`).
- Full iPhone Simulator suite: **205 tests, zero failures** (`/tmp/ameluma-toolbox-phone.log`).
- Focused native Mac panel tests: **nine passed** (`/tmp/ameluma-toolbox-mac.log`). The previous full Mac native screenshot harness exception remains unresolved; this run does not claim to resolve it.
- Unsigned Release builds succeeded for Mac and iOS/iPadOS (`/tmp/ameluma-toolbox-mac-release.log`, `/tmp/ameluma-toolbox-ios-release.log`). No signing changes.
- Live iPad Simulator check used an isolated synthetic project at `/tmp/ameluma-toolbox-ipad-live`. Opened the photo, activated Privacy, opened and dismissed Options, then switched to Annotate and Adjust. The native screenshot showed the popover arrow attached immediately below Options, and the accessibility state confirmed the same photo and active tool throughout. No personal image/session data was edited.
- Native final full-shell captures: `docs/screenshots/ipad-toolbox/` (ignored local artifacts). The final minor popover polish removes duplicate effect/shape controls from the detailed panel and shortens its empty state; these controls already appear in the context row.

Physical iPad/Pencil, VoiceOver and larger-text interaction still need device verification. These results are not a claim that every iPad editor was exhaustively tested or that all accessibility and device performance work is complete. No commit or push was made.

Final compact-popover build and focused iPad regression rerun passed: nine tests, zero failures (`/tmp/ameluma-toolbox-final-panel-polish.log`). `git diff --check` passed.
