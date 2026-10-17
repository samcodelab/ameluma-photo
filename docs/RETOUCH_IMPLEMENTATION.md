# Retouch: Heal and Clone

Implemented in the existing Editor toolbox, overlay transaction/history and shared FramepebbleCore processing engine. No cloud service, third-party dependency, source registry, signing change or storage rename was introduced.

## Behaviour and processing

- Heal chooses nearby color-compatible texture unless the user explicitly sets a source. Its Metal Core Image kernel transfers source detail with low-frequency destination color/light adaptation. This is texture-based healing, not generative inpainting or a claim to duplicate Photoshop's proprietary algorithms.
- Clone samples a chosen source with a fixed per-stroke offset, a rounded continuous brush path, feathered edges and opacity. Aligned sampling maintains the offset between strokes; unaligned sampling restarts at the chosen source. Set Source works with touch or pointer; Mac has an Option sampling modifier. Numeric source coordinates and accessible canvas actions provide alternatives.
- Every stroke captures mode, normalized path, source location, diameter, hardness and opacity. Automatic source decisions are captured before committing, so output dimensions do not cause a new automatic selection during export.
- Retouch runs after framing and before privacy/annotations/watermark. Source sampling respects existing privacy masks; it cannot reveal unmasked originals from beneath a displayed mask.
- Preview/export, GIF frame rendering and collage photo rendering share the same processor. Strokes are added as private history transactions, can be undone/redone/removed individually, and enter project history only on Apply. Cancel keeps prior applied work.
- Modern runtime-compiled stitchable Metal Core Image kernel, supported by the app's deployment baseline. Deferred graphs checkpoint every eight strokes into floating-point images. Per-stroke mask buffers are limited to the painted region; cancellation is checked during processing. Existing image dimension/memory limits still apply.
- Codable configuration gains a default-empty `retouchStrokes` field and an explicit sparse patch/category. Existing configurations decode unchanged. Stored instructions contain coordinates, not another source bitmap. Retouch is photo-scoped and omitted from new batch presets; export profiles retain the requested photo's strokes.
- Editing drafts now force the iPad navigation sidebar closed through the split-view binding. Native captures exposed a race in the previous save/restore visibility callback; it could briefly shrink the canvas during a draft.

## UI

Retouch lives beside Adjust, Crop, Privacy and Annotate. Landscape iPad uses the existing right tool rail and inspector; portrait uses anchored options. iPhone uses a canvas-first layout with a compact Heal/Clone control, Set Source and an expandable native Brush panel. Source/brush indicators provide painting feedback. Automatic sampling is off the main actor, and pending preview work is visible.

## Verification

- Shared Core suite: **117 tests passed**, including new actual-pixel checks for Clone dabs/continuous strokes, opacity blending, destination color matching for Heal, protected source sampling, automatic sample determinism, graph checkpoints, invalid data, cancellation, preview/export coordinates, encoded output reopening and unchanged source bytes.
- Full iPad Simulator suite: **211 tests, one Photos-permission integration skip, zero failures** (`/tmp/ameluma-retouch-ipad-metal-final.log`).
- Full iPhone Simulator suite: **211 tests, zero failures** (`/tmp/ameluma-retouch-phone-metal-final.log`).
- Focused native Mac app-state suite: **12 passed** (`/tmp/ameluma-retouch-mac-tests.log`).
- Full Mac native suite: **32/33 passed**. The existing native screenshot harness again threw XCTest `InvalidTransition { phase: idle, targetPhase: failed(deinit) }` (`/tmp/ameluma-retouch-mac-full.log`). This remains unresolved; it is not counted as a passing visual suite or assumed harmless.
- Both unsigned Release targets built successfully; signing remains unchanged. Final logs are listed below.
- Native iPad/phone captures inspected. The first phone capture exposed oversized controls; these were replaced by the canvas-first Brush panel layout. Local synthetic captures are under `docs/screenshots/retouch/` (ignored artifacts).
- Live iPad Simulator, isolated synthetic review root `/tmp/ameluma-toolbox-ipad-live`: opened Retouch, invoked a Heal dab through the actual canvas accessibility action, verified Strokes (1), Undo to zero, Redo to one and Apply. The saved Session.json contains that Heal stroke and captured source coordinates. No personal project or images were used.
- Two release-tool tests passed. Static preflight has no failures; existing public privacy/support URL and distribution-signature verification blockers remain. No distribution actions were attempted.

## Practical limitations

Strokes currently use final-output coordinates, like the existing overlays; changing framing, rotation or canvas can move the photo under a repair. The tool and Help explicitly tell users to review the result. This is not source-space brush reprojection. Heal's automatic sample is a nearby deterministic texture/color match; difficult boundaries or large removals require manual source selection and smaller strokes. Maximum 200 strokes per photo / 2,000 recorded points per stroke. Older application builds do not understand these new instructions and should not be used to resave a retouched project.

Physical-device Pencil strokes/pressure, broad photographic quality evaluation, Intel Mac GPU coverage and large-image device performance remain unverified. Clone's pixel behavior is covered by rendering tests; the live check above exercised Heal through an accessibility action rather than a physical brush gesture. No claim of Photoshop feature parity, automatic object removal or production device benchmarking is made.

## Final delivery checks

- Core, including final zero-distance touch/pointer dab coverage and extended-color-safe Metal arithmetic: **117 passed** (`/tmp/ameluma-retouch-core-delivery.log`).
- Final iPhone UI, processing and app-state checks: **31 passed** (`/tmp/ameluma-retouch-phone-final-check.log`). The Retouch visibility fixture restores its native photo aspect instead of inheriting an earlier test's rotated Fit canvas; it now requires more than 15% source-photo area. Retouch uses 12-point canvas margins; masks/annotations retain the space needed for handles.
- iPad final native capture/panel checks: **13 passed** (`/tmp/ameluma-retouch-ipad-delivery-tests.log`).
- Final unsigned Release builds: `/tmp/ameluma-retouch-ios-delivery-final.log` and `/tmp/ameluma-retouch-mac-delivery-final.log`, both succeeded.
- Full simulator suites remain as recorded above; the later focused checks cover the final canvas/label/brush polish. The final local phone capture replaces the earlier controls-first image.
- `git diff --check` passed. No commit or push.

Implementation references: [Adobe's iPad retouch workflow](https://helpx.adobe.com/ph_fil/photoshop/ipad/retouch-and-adjust-images/retouch-photos-ipad.html) informed the sample-then-paint interaction; [Apple's Metal kernel API](https://developer.apple.com/documentation/coreimage/cikernel/kernels%28withmetalstring%3A%29) is used for the local healing kernel. No competitor implementation or artwork was copied.

Final Core rerun also checks substantial reduction of a concrete bright blemish on a blue destination: **117 passed** (`/tmp/ameluma-retouch-core-complete.log`). Final static preflight again reports no failures and the same four distribution blockers.

## 17 October sampling and iPad presentation

New strokes use sampling version 2. Automatic Heal compares robust linear-RGB colour and variation in rings outside the initial painted area against nearby candidate patches, using one bounded 256-pixel analysis bitmap. It no longer ranks only eight patches against the blemish’s own mean colour. This is a local heuristic, not semantic clothing/skin segmentation or content-aware synthesis; mixed boundaries, large objects and long strokes may still need a smaller brush or explicit Set Source. Sampling version is optional in Codable: absent/1 uses the previous algorithm, and existing explicit sample coordinates remain authoritative. A material-boundary regression uses a skin-coloured button on red fabric beside skin; it verifies fabric selection, repeatability, version persistence and legacy behavior.

iPad drawing tools now default to the adjacent floating controls; detailed options use an anchored popover instead of automatically expanding a sidebar. The ordinary Adjust surface puts the slider above its secondary actions, giving the slider the full available width. Parent toolbox ownership prevents an inspector-induced compact size class from creating a second filter strip.
