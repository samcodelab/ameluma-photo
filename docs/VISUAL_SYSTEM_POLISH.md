# Visual system polish — 16 October 2026

This pass builds on the demo-workspace layout work. It establishes shared visual conventions in `SharedUI/PanelComponents.swift` rather than adding a theme framework or replacing native forms.

## Implemented conventions

- **Photo stage:** a neutral, adaptive canvas surround in the photo editor, GIF preview and Mac collage stage. The image remains the strongest colour; light and dark appearances retain distinguishable canvas boundaries.
- **Toolbars:** one rounded selection treatment, shared minimum hit areas (32 points on Mac, 44 on touch platforms), consistent icon weight, pointer hover and pressed feedback. Reduced Motion disables the short feedback animations. Disabled actions remain visibly disabled.
- **Selection:** photo tabs, GIF frame selections and collage tabs use the same accent strength and corner treatment. These remain distinct state models; visual consistency does not merge operation inputs, active photos or creation frames.
- **Contextual surfaces:** common padding and radius for immediate tool options; existing bounded and dismissible placement is retained. Wide Adjust places Details and Close beside Quick Fix rather than in a separate row. Detailed properties remain optional. Creation inspectors have a consistent native bar surface.
- **Menu rows:** GIF speed/playback values reserve their actual width instead of wrapping unnecessarily; at accessibility sizes the label and menu stack.
- **Hierarchy:** compact inspector headings, quieter photo-tab typography, middle-truncated filenames and hierarchical thumbnail status symbols. Warning and selection indicators remain visible.
- **Values:** read-only percentages round to whole percentages and general values show up to two decimal places. Numeric adjustment entry retains two-decimal precision without unnecessary trailing zeros. Display formatting never rounds stored settings.

## Compatibility and scope

No processing, source, schema, storage, signing, selection or export changes. No new dependency. Native menus, keyboard focus, accessible labels and selected traits remain. No animated transitions between editor states were added.

This is an incremental visual-system implementation, not a claim of parity with Photomator, Affinity or Photoshop. Device touch/Pencil usability, complete VoiceOver traversal and measured contrast still need physical-device verification. Published competitor pictures are design references, not a controlled usability benchmark.

## Verification

Results and fresh captures are recorded in the accompanying visual-system evidence report. Historical test counts and prior screenshots are not evidence for this change. The previously unresolved long Mac mixed native capture remains outside the focused test run; this pass does not claim to resolve it.

### Results from this pass

- Core: **117 passed**, zero failures (`/tmp/ameluma-identity-core.log`).
- Final focused Mac run: **24 passed**, zero failures (`/tmp/ameluma-identity-verified-mac.log`).
- Final focused iPhone and iPad runs: **25 passed each**, zero failures (`/tmp/ameluma-identity-verified-phone.log`, `/tmp/ameluma-identity-verified-ipad.log`). Includes compact/accessibility layouts, independent scope/draft regression coverage, new readout tests and native demo/creation captures.
- **33 fresh demo captures**: 10 Mac, 13 iPad, 10 iPhone. The evidence page selects representative views and two additional accessibility/landscape test fixtures. Final GIF playback is single-line at normal iPad size; wide Adjust has no separate utility row.
- Both unsigned Release targets **built successfully** (`/tmp/ameluma-identity-release-{mac,ios}.log`).
- Release-tool tests: **2 passed**. Static preflight: **zero failures, four submission blockers** (public privacy/support URL verification and both distribution signatures). Signing was not changed.
- `git diff --check` passed. Local evidence page checked at 1500 × 1000 and 390 × 844: no horizontal overflow, no broken embedded images; enlargement and Escape dismissal work.

Native Vision cache `MDB_MAP_FULL` warnings still appear during Mac demo indexing. Simulator runtime accessibility warnings also appear. Passing focused tests does not resolve these warnings or the older excluded Mac mixed capture exception. No physical-device usability or full accessibility certification is claimed.

[Before/after and current captures](VISUAL_SYSTEM_POLISH_2026-10-16.html)
