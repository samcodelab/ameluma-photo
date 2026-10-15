# Editor interaction review — 14 October 2026

The previous editor required too much indirect adjustment and made edit completion ambiguous. Direct manipulation must be the primary interaction, with exact numeric values as an optional alternative.

## Established conventions

[Apple Preview](https://support.apple.com/en-ca/guide/preview/prvw1501/mac) supports dragging shapes and resizing through handles; its crop frame can also be moved and resized. [Pixelmator Pro](https://support.pixelmator.com/pixelmator-pro-user-guide/work-with-layers/resize-rotate-and-flip-layers) provides manual resize handles alongside numerical dimensions and rotation controls. These support a clear principle: manipulate the object where it appears, rather than repeatedly translating movement into inspector values.

## Framepebble changes

| Interaction | Previous friction | Implemented behaviour |
| --- | --- | --- |
| Workspace | Small editing presentation | Main Mac/regular-width iPad workspace; full-screen iPhone |
| Creation | Repeated Add Area step | Draw creates an area, then selects it; empty-canvas click resumes Draw |
| Selection | Indirect geometry controls | Select tool, drag body to move, eight resize handles, rotation handle |
| Precision | Geometry sliders dominate | Optional collapsed numeric fields; effect strength and opacity remain sliders |
| History | Draft and global shortcuts conflicted | Local grouped gesture Undo/Redo; native Mac menu routes to active editor |
| Removal | Difficult to remove an area | Delete button, context action, keyboard Delete on focused canvas, reversible |
| Completion | Escape kept unwanted edits | Apply commits once; Cancel, Escape and Close discard the draft |
| Finding private images | Edited arbitrary current photo | Hide Something filters actual privacy flags; context menu opens a chosen photo |

Privacy areas and annotations use the same direct transformation controls. Normalised shared geometry keeps their export representation independent of preview size. This review does not claim that every collage, watermark or crop interaction has professional-editor parity.

## Remaining flexibility gaps

Group selection/transformation and snapping remain opportunities. Keep proportions now constrains corner and edge resizing through shared geometry; Mac Shift-drag temporarily enables it. Boundary clamps preserve aspect ratio, although reaching the canvas edge can move the opposite anchor. Numeric dimensions remain independently editable. Keyboard nudging is implemented: focused Mac canvas arrows move the selected object by 0.1% of the output, Shift by 1%; a held key is one reversible interaction. The canvas also exposes directional VoiceOver actions on both platforms. They are not advertised as implemented. The gallery already offers preview-size controls. The embedded privacy editor now supports 1–4× fit-relative canvas zoom, native horizontal/vertical scrolling to pan, and Fit. Zoom changes only viewing scale, not exported geometry.

## Validation

Real Mac interaction on synthetic images verified repeated drawing, selection, moving, corner resizing, rotation, Delete, local Undo/Redo, cancellation and one-step project Apply/Undo. Core geometry and editing-session tests exercise the shared state. iOS Simulator tests cover shared rendering and workspace transitions; physical iPhone/iPad touch validation remains outstanding.

## Workspace follow-up

The next revision separates a persistent Select/Draw tool rail, the central canvas and a contextual selection inspector on Mac and regular-width iPad. An Objects list supports direct selection and deletion of every mask and annotation. Unselected objects no longer each expand their properties into a long form. The iPhone retains a compact tool switch with the same object model and an Objects list. These are functional controls over existing draft state; no decorative future tools are shown. The rail can accommodate additional tools while the inspector remains specific to the current selection.

Drawing now immediately selects the new mask or annotation. Clicking the selected area keeps it selected; clicking empty photo space clears selection and returns to drawing without creating an extra object. The next drawing keeps the last selected effect/shape or annotation kind. Verified with live Mac synthetic-image interaction.
