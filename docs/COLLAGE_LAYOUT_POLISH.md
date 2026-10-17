# Collage layout refinement

16 October 2026. A focused response to the supplied Mac collage screenshot. The target is disciplined panel hierarchy and alignment, without adding a professional editing toolset.

- Mac document tabs, Add Photos, Actions, Undo/Redo and Export now share one compact row.
- The redundant “Collage tool” label is hidden. Collage / Photo / Output remain accessible native tabs.
- Canvas settings share a fixed label column. Width and height sit together with one pixel unit. Appearance settings use aligned slider/value rows rather than three separate label/slider stacks.
- Title is an expandable section, opened for existing titles. Collapsing it preserves the title and its colour. Shape, Text and Photo Mosaic remain in Actions → Create.
- The canvas uses its available space without the former arbitrary 1000-point cap. A quiet status bar shows output size, photo count and view-only Fit/zoom controls. Zoom is relative to Fit, not a claim of full-resolution pixel inspection; Actions → Inspect Pixels retains that workflow.
- Viewing zoom is local UI state. It does not change project dimensions, framing instructions, source files, saved output or rendering. Scroll anchoring centres the viewing surface when its size changes.

Native fixtures were inspected at 1440 × 900 and 1040 × 700, including an existing title. Local screenshots are under `docs/screenshots/collage-polish/` (ignored test artifacts): [single photo](screenshots/collage-polish/mac-single-photo.png), [title](screenshots/collage-polish/mac-title.png), [narrow window](screenshots/collage-polish/mac-narrow.png). The fixture uses generated imagery; it is not an identical-source comparison with the supplied screenshot.

Validation: Mac native suite **27 tests passed**; iPhone **202 passed**; iPad **202 tests, one permission-dependent skip, zero failures**. Final unsigned Mac and generic iOS/iPadOS Release builds succeeded. No Core processing code, schema, storage path, dependency or signing setting changed. A stale reference to the replaced inline art disclosure was caught during final compilation, removed and the builds rerun successfully.

Logs: `/tmp/ameluma-collage-polish-final-mac.log`, `/tmp/ameluma-collage-polish-phone.log`, `/tmp/ameluma-collage-polish-ipad.log`, `/tmp/ameluma-collage-polish-release-mac.log`, `/tmp/ameluma-collage-polish-release-ios.log`. The screenshots come from the final successful Mac `.xcresult` bundle.

Live selection by bundle ID was rejected by automatic approval review because multiple Ameluma instances made it ambiguous whether the isolated review app or a personal session would be selected. Final visual validation used isolated native test captures. Live zoom/scroll interaction, physical-device touch and a complete accessibility audit remain unverified; this change does not claim Photoshop-equivalent usability certification.

Changes remain uncommitted and unpushed.
