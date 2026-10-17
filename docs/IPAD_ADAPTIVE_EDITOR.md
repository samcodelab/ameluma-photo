# Adaptive iPad Editor and privacy tracing — 16 October 2026

This supersedes the fixed horizontal toolbox/portrait-only options approach in IPAD_TOOLBOX_REVIEW.md.

## Changes

- Landscape at widths of at least 900 points uses a narrow right-edge toolbox with the current tool's settings immediately to its left. The canvas occupies the remaining region. Photo adjustments use the compact shared controls rather than large grouped-form rows. Panels can collapse and reopen from their tool.
- Portrait, narrow multitasking and accessibility text sizes retain a horizontal toolbox. Ordinary photo tools open anchored popovers from the corresponding tool. Privacy/annotation common controls stay underneath the toolbox; detailed settings open from Options. Large-text anchored tools stay outside transient menus so their popover anchors remain available.
- Both presentations use the same workspace, photo targets, draft resolution and processing definitions. No Core model defaults or persistent schemas changed.
- Newly drawn privacy areas start with **Pixelate** and **Freeform**, also listed first in their menus. A finger/Pencil trace closes when lifted and defines a normalized polygon. Rectangle and ellipse remain available. Existing saved areas retain their shape/effect.
- Incomplete, non-finite, tiny or degenerate traces do not create a rectangular fallback mask. The accessible centred-area action supplies a complete closed outline.
- The shared renderer still closes and flattens mask paths using existing processing. Pixelation does not guarantee concealment; existing privacy guidance remains available.

## Verification

- Full iPad Simulator suite: **207 tests, one Photos permission integration skip, zero failures**. Log: `/tmp/ameluma-adaptive-ipad-final.log`.
- Full iPhone Simulator suite: **207 tests, zero failures**. Log: `/tmp/ameluma-adaptive-phone.log`.
- Native Mac focused panel suite: **11 tests passed**. Log: `/tmp/ameluma-adaptive-mac.log`.
- Final iPad compact layout/panel rerun: **12 tests passed**. Log: `/tmp/ameluma-adaptive-ipad-polish.log`.
- Unsigned Mac and iOS/iPadOS Release builds passed (`/tmp/ameluma-adaptive-mac-release.log`, `/tmp/ameluma-adaptive-ios-release.log`).
- Added regression checks for orientation/large-text adaptation, default menu ordering, normalized triangular mask geometry, points inside/outside the traced contour, rejection of degenerate input, and unchanged legacy rectangle/cover mask serialization.
- Inspected native portrait/landscape captures from the full application shell. Local images: `docs/screenshots/ipad-adaptive/` (ignored synthetic verification artifacts).
- Live Simulator check used only `/tmp/ameluma-toolbox-ipad-live`, an isolated synthetic project. Verified portrait Adjust popover opening/dismissal, initial Privacy Pixelate/Freeform choices, actual rotation into landscape, adjacent settings, collapse and reopen preserving the choices.

Physical iPad/Pencil freeform strokes and VoiceOver interaction remain unverified. The native UI automation API does not provide a multi-point curved stroke; trace geometry is covered by automated tests. Earlier Mac screenshot-harness exceptions remain unresolved; focused Mac tests and successful compilation do not constitute a passing full Mac visual suite. No commit, push or signing changes.

Final iOS/iPadOS Release rebuild also passed after the last compact/large-text polish: `/tmp/ameluma-adaptive-ios-final-release.log`. `git diff --check` passed.
