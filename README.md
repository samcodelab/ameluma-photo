# Ameluma Photo

**Your photos. Your way.** A native, local photo toolbox by Broad Frame Studio for macOS 15+, iOS 18+ and iPadOS 18+. Open `Framepebble.xcodeproj` and choose **FramepebbleMac** or **FramepebbleiOS**. Both targets link the same local `FramepebbleCore` Swift package; there are no third-party runtime dependencies.

## Implemented workflows

- Import multiple files, recursive folders, Finder drops and item-based Photos selections. Native decoder capabilities determine JPEG, PNG, HEIC, TIFF and WebP availability; input validation uses content, not extensions.
- Browse the lazy grid, find actual Vision-classified content, filter favourites/edited/review images, and select matching images.
- Switch to **Frame**, drag inside fixed output thumbnails, pinch or Option-scroll to zoom, then **Refine** for precision controls. Grid and precision editing use one normalized crop state. Compare original and processed views with the comparison slider.
- Resize using Fit, Fill, Stretch, Canvas or Preserve Aspect Ratio; choose custom pixels or presets, prevent upscaling, rotate, flip and straighten. Scope controls apply settings to the whole library, selected images, search results or the current image.
- Use native Vision Smart/Keep Subjects framing and review flagged results. Batch auto-framing preserves manual overrides; explicit per-image Smart actions can replace them. Undo/Redo and explicit resets are available.
- Add text or image watermarks with relative sizing, colour, opacity, rotation, nine positions, offsets, margins and tiling. Save watermark and export presets.
- Export using registered native encoders, quality presets, optional bounded target-size encoding, supported metadata policies and sRGB/source-RGB colour management. Export one or multiple profiles into separate folders.
- Adjust exposure, brightness, contrast, saturation, warmth, highlights and shadows. Quick Fix uses bounded lighting/colour heuristics and native automatic suggestions; all corrections are editable and undoable.
- Create multiple tabbed collages with 74 gallery layouts, shape/text art and local reference photomosaics; reframe cells, swap/add/remove photographs, adjust backgrounds/spacing/borders/corners/shadows, and add titles/captions. Collages remain editable until rendering.
- Draw text, arrows, lines, rectangles, ellipses and freehand annotations. Hide selected areas with opaque covers, blur, pixelation or frosted effects; use precision cropping to exclude unwanted content.
- Review final outputs before native sharing, exclude files, approve a selection, copy a processed image, save reviewed images to Photos or reveal files in Finder. Sensitive-content detection is not enabled in this unsigned build; manual review does not certify safety.
- Configure Mac folder Automations using security-scoped bookmarks, reconciliation scans and FSEvents hints. Automatic/review modes, stable-file checks, hash history, retry, test preview and menu-bar monitoring use the Studio engine.
- Save/open project instructions, browse recent local projects and relink selected missing sources. Private mode bypasses memory thumbnail caching and offers workspace concealment. Repeated byte-identical imports can be skipped or imported anyway.
- Retain validated outputs through cancellation and partial failures; retry pending requests. Sources, edits, classifications, presets and pending export requests are saved locally for session restoration.

## Project layout

```text
Apps/macOS/          Native panels, Finder drop, sharing, FSEvents and automation adapters
Apps/iOS/            PhotosPicker, Files, Photos saving and lifecycle adapter
Apps/Shared/         MainActor session coordinator
SharedUI/            Library/grid, framing/precision, comparison and inspectors
Packages/FramepebbleCore/
  Sources/           Models/history, processing, adjustments, overlays, collages, privacy, Vision, search, watermarks, persistence
  Tests/             Shared geometry, codecs, Vision, watermark and export tests
Tests/               App interface-state, 100-image and native automation integration tests
Framepebble.xcodeproj Native targets and app-hosted Simulator test scheme
tools/               Standard-library project generator
docs/                Architecture, specification, roadmap, test plan, help and privacy
```

The checked-in project opens without a generator installation. `python3 tools/generate_project.py` regenerates it deterministically. Signing teams and App Store records are deliberately unconfigured.

## Build and test

```sh
swift test --package-path Packages/FramepebbleCore
xcodebuild -project Framepebble.xcodeproj -scheme FramepebbleMac -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Framepebble.xcodeproj -scheme FramepebbleiOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Framepebble.xcodeproj -scheme FramepebbleMacTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Framepebble.xcodeproj -scheme FramepebbleCoreiOSTests -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Choose an installed Simulator. Swift 6 language mode is used with installed Xcode 27 / Swift 6.4. The macOS gesture adapter uses isolated deinitialization, supported by this compiler. See [TEST_PLAN](docs/TEST_PLAN.md) for evidence and required release checks.

## Safety and privacy

Processing always starts from an unchanged private source snapshot. No images are uploaded by Framepebble. No accounts, advertising, analytics or telemetry are implemented. Mac browser drops can download an explicitly dragged HTTPS image link when the browser does not supply image bytes; cookies, stored credentials and local images are not sent. Editing and local imports work offline. A serial renderer, bounded thumbnail cache and downsampled editing surfaces control image memory. Local source snapshots use disk space once per import and currently remain in Application Support until removed outside the app.

Exports are staged on the destination filesystem, decoded for validation and published with an exclusive rename. Source aliases and existing names are never replaced. Unsupported publication operations fail visibly. Metadata policies copy or remove selected supported dictionaries; they do not guarantee anonymity or universal metadata removal. JPEG and HEIC outputs flatten alpha.

PhotosPicker, Files and Share are Apple-managed services. iCloud-only selections may be downloaded by the system; an explicitly selected cloud destination or Share action may synchronize at the user's direction. Local processing works offline with locally available files. Photos saving requests add-only permission. See [PRIVACY](docs/PRIVACY.md).

## Current limits

This is a substantial development build, not a completed commercial release. Physical-device performance, Pencil/trackpad testing, sandbox/signing validation, VoiceOver/localization, large real-world collections, provider-specific atomic publication, Photos format support and catastrophic interruption recovery still require QA. Project copies and relinking are implemented; storage accounting/cleanup and comprehensive bookmark repair remain unfinished. There is no arbitrary semantic search, foreground-mask framing, export-profile destination bookmark UI or universal WebP encoder. No unavailable features are presented as working controls. See [roadmap](docs/DEVELOPMENT_ROADMAP.md).

Release targets now share `com.broadframestudio.framepebble`. Debug retains the earlier Mac/iOS identifiers to preserve development data. Apple's current [universal-purchase guidance](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms) requires the same bundle ID and shared app record; configure a single shared App Store record and signing team before distribution. No App Store records were created.

The intended business model is a one-time universal purchase at a target A$29.99. No store price, purchase record, subscription or in-app purchase has been configured. See [latest implementation report](docs/TOOLBOX_IMPLEMENTATION_REPORT.md).

The latest interface simplification and outstanding usability checks are documented in [UX review](docs/UX_REVIEW.md).

App Store submission is on hold; see the [reviewer audit](docs/APP_STORE_REVIEW_AUDIT.md) for fixes, unsigned archive evidence and remaining release gates.

Mac accepts browser image-data drops and explicitly dropped HTTPS image links, alongside Finder files and nested folders. Web-only downloads are capped at 25 MB; inaccessible/login-protected pages should be saved in the browser first. See [browser drop support](docs/BROWSER_DROPS.md).

Network-folder import now copies and hashes each source in one pass on a separate acquisition actor. Images appear and can be edited incrementally; a pinned progress strip reports copying, discovery and cancellation. Server/network performance still limits transfer speed.

Recent implementation details: [incremental imports](docs/INCREMENTAL_IMPORT.md), [temporary privacy review](docs/SENSITIVE_CONTENT.md), and [local signing](docs/SIGNING.md).

## Preview size and workspace cleanup

Use Preview size above the gallery to enlarge or shrink tiles. This changes display size only; exported dimensions and crop geometry are unchanged. In Projects, Close Project saves work to Recent Projects and empties the workspace. Clear Imported Photos discards current edits after confirmation, stops processing, saves an empty session and removes unused UUID-named regular snapshots only from Framepebble’s private Sources folder. Originals, exports, saved project files and snapshots they reference are retained. Symlinks and unknown filenames are skipped. An unreadable saved project stops cleanup. There is no secure-deletion claim. To preserve current edits, save a project copy before clearing.

Cross-platform interface review and validation limits: [UX review](docs/UX_REVIEW.md).

## Four workflows and scoped edit safety

Batch Edit, Editor and Collages share one library; Mac also offers a dedicated Automations workspace. Field-scoped overrides prevent unrelated photo edits from being overwritten and retain batch inheritance. Schema 4 migrates versions 2/3 while preserving effective output. Sharing sessions contain only successes from the requested operation. Export plans include profile counts and final-resolution encoded previews. See [workflow behaviour and limits](docs/WORKFLOWS_AND_EDIT_SAFETY.md).

The completed UI/UX polish pass and native layout captures are documented in [UI_UX_COMPLETION_AUDIT.md](docs/UI_UX_COMPLETION_AUDIT.md), including physical-device, accessibility and release-validation limits.


## Library and tabbed Editor

The Photo Library is the gallery. Batch Edit, Editor, Collages and Mac Automations are separate workspaces sharing its sources and editing state. Privacy Review is a library filter; Privacy is an Editor tool, available from the editor toolbar or a photo’s context menu.

Mac and iPad Editor show explicit, closable photo tabs. iPhone uses an Open Photos menu. Tabs are unique per source and independent of gallery focus, filters and batch membership. Export/share targets only the active editor photo. Closing a tab preserves all project edits and original files; closing the last returns to the gallery. Optional tab IDs and the active tab are saved in schema-4 projects, with absent fields defaulting to an empty session in older projects. Per-tab tool context is retained during the current app session and starts at Adjust after reopening a project. Apply or cancel an overlay draft before switching tabs or workspaces.


## Product naming

The application is **Ameluma Photo**. Its iPhone/iPad home-screen display name is **Ameluma**. The Mac app bundle is `Ameluma Photo.app`; the iOS bundle is `Ameluma.app`. Xcode project/target names, Swift modules, bundle identifiers, security-scoped references and legacy Application Support locations retain their existing Framepebble identifiers for compatibility. No source or saved-project migration is required for this branding change.

See [Collage tools and limits](docs/COLLAGES.md) for photo-filled shapes/text, reference mosaics, persistence and export behaviour.
