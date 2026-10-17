# iPad layout correction — 16 October 2026

The detached options-sheet design below is superseded by [the contextual toolbox correction](IPAD_TOOLBOX_REVIEW.md).

The supplied portrait screenshots confirmed that navigation and fixed tool panels were consuming the editing surface. Privacy also repeated its title and put long instructions and Apply & Crop into a toolbar too narrow to contain them.

Changes:
- Editing starts with the navigation sidebar collapsed; workspace browsing still exposes navigation. The sidebar has a bounded 220–280 point width. Entering a Privacy/annotation draft temporarily collapses navigation and restores the prior visibility on exit.
- iPad navigation titles use the inline size.
- Embedded Privacy/annotation editing only shows the 300 point inspector alongside the canvas at widths of at least 920 points. Portrait, narrow multitasking and accessibility text sizes open the same options in a native sheet. Drafts, object selection and history stay in the original editor.
- Removed the repeated Privacy heading, filename and gesture instructions from the action toolbar. Apply & Crop has an accessible crop icon; the primary Apply action remains at the bottom. Filename and Fit/zoom controls remain in the canvas status bar.
- Batch Edit no longer has duplicate iPad bottom settings and Rotate/Refine rows. Settings remain in the top toolbar; individual photo actions remain available through the gallery/context menus. Reframe thumbnails shares the preview controls row, and the permanent touch hint is removed on regular-width layouts.

Verification:
- Full iPad Simulator suite: 203 tests, one Photos permission integration skip, zero failures. Log: `/tmp/ameluma-ipad-space-final.log`.
- Unsigned iOS/iPadOS Release build succeeded: `/tmp/ameluma-ipad-space-ios-build.log`.
- Mac compiled; 27 of 28 native tests passed. Native hierarchy capture failed with XCTest `InvalidTransition { phase: idle, targetPhase: failed(deinit) }`, reproduced in an isolated rerun. Seven focused panel behavior tests passed in that rerun. This remains an unresolved capture/test failure, not a passing Mac visual check.
- iPad full-shell captures now cover Batch portrait, Privacy portrait, selected mask portrait and Privacy landscape, in addition to prior narrow/accessibility checks. These use synthetic local images, not personal photos.

Physical iPad touch, Pencil, keyboard, VoiceOver and interactive sheet transitions still require device verification. The earlier live Mac app selection approval restriction remains; these changes were checked through isolated native test hosts.

Final focused rerun after correcting independent draft fixtures: eight tests passed, zero failures (`/tmp/ameluma-ipad-space-captures-final.log`). Visually inspected the final portrait selected-mask capture; handles and the larger photo remain visible without a side inspector. Captures are in `docs/screenshots/ipad-space/` (ignored local verification artifacts).
