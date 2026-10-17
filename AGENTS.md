# Framepebble — Engineering Instructions

## Product

Framepebble is a native image batch-processing application
developed by Broad Frame Studio.

Supported platforms:
- macOS 15+
- iOS 18+
- iPadOS 18+

Language: Swift
UI: SwiftUI
Architecture: Shared Swift Package with platform-specific apps

The product must support Mac, iPhone and iPad without
duplicating the image-processing engine.

## Core Product Principles

1. All image processing happens locally.
2. Never upload, transmit or collect user images.
3. No accounts, analytics, advertising or telemetry.
4. All operations must be non-destructive.
5. Original images must never be modified.
6. Processing results must be predictable.
7. The application must handle large image batches.
8. User interfaces must feel native on each platform.
9. Prefer Apple frameworks to third-party dependencies.
10. Maintain compatibility with Apple's App Store requirements.

## Architecture

Use a shared Swift package named FramepebbleCore.

The package must compile for macOS, iOS and iPadOS.

Do not use AppKit or UIKit inside FramepebbleCore.

Use platform-independent Apple frameworks including:

- Foundation
- Core Image
- Core Graphics
- ImageIO
- Vision
- UniformTypeIdentifiers
- Accelerate where appropriate

Use SwiftUI for shared interface components.

Platform-specific features must be implemented through
separate adapters.

Examples:

macOS:
- NSOpenPanel
- NSSavePanel
- Finder drag and drop
- Security-scoped bookmarks
- Multiwindow support

iOS/iPadOS:
- PhotosPicker
- FileImporter
- FileExporter
- Photos framework for saving to Photos
- Share sheets
- Touch gestures
- Adaptive navigation

Platform differences must not leak into the processing engine.

## Image Processing Pipeline

Use a deterministic processing pipeline:

Import
→ Decode
→ Apply orientation
→ Resize
→ Crop / Canvas
→ Watermark
→ Colour conversion
→ Encode
→ Validate
→ Export

Processing must always operate from the original source.

Never repeatedly transform previously compressed output.

The preview and final export must use the same
transformation definitions.

Preview resolution may be reduced for performance.

## Image Import

Support:
- JPEG
- PNG
- HEIC
- TIFF
- WebP where native support is verified

Support multiple-file import and folder import where
the platform permits.

Do not assume access to the entire Photos library.

On iOS, prefer PhotosPicker to avoid unnecessary
full-library permissions.

Respect security-scoped file access and platform
sandbox requirements.

Imported images must not be modified.

## Batch Processing

Support:
- Resize
- Crop
- Rotate
- Flip
- Format conversion
- Compression
- Canvas resizing
- Watermarking
- Metadata handling

Batch settings apply to all selected images.

Individual image overrides must be stored separately.

Changing batch settings must not silently discard
individual crop or framing adjustments.

Provide explicit reset controls.

## Auto-Framing

Use Apple's Vision framework.

Investigate:
- Attention-based saliency
- Object-based saliency
- Foreground instance masks
- Face detection

Auto-framing must work entirely on-device.

Supported framing modes:

1. Centre
2. Smart
3. Keep Subjects
4. Manual

Always provide a deterministic fallback.

If subject detection fails, use centred framing.

Never silently crop away important content when the
application can detect an obvious problem.

Allow individual manual adjustment.

Do not require cloud-based AI.

## Cropping

Cropping must be resolution independent.

Store crop geometry in normalised coordinates.

Support:
- Aspect ratio presets
- Custom aspect ratios
- Drag to reposition
- Pinch or scroll to zoom
- Manual rotation
- Reset to batch defaults

Use the same crop geometry on every platform.

Only gesture and interaction adapters may differ.

## Watermarking

Support text and image watermarks.

Properties:
- Content
- Position
- Size
- Opacity
- Rotation
- Margins
- Relative scaling

Use a nine-position alignment grid.

Watermark dimensions should be relative to final
output dimensions.

Watermarks must be applied after image framing.

Use the same rendering implementation on macOS
and iOS.

## Compression

Support:
- Quality presets
- Custom quality settings
- Target file size where feasible

Do not promise that arbitrary images can always
meet a requested file size.

Report failures clearly.

Ensure image format capabilities are validated.

## Export

Support:
- File format selection
- Destination selection
- Naming templates
- Export profiles
- Metadata options
- Collision handling
- Progress reporting
- Cancellation

Export must never overwrite source images.

Detect source/destination aliases where practical.

Use staging files and safe publication procedures.

Do not report export success until output validation
has completed.

Handle partial batch failures without losing
successful results.

On iOS, support exporting to Files and Photos.

On macOS, support user-selected folders.

## Project Model

Keep these concepts separate:

- SourceAsset
- BatchSettings
- ImageOverride
- CropConfiguration
- WatermarkConfiguration
- ExportProfile
- ProcessingJob
- ProjectDocument

Use Codable models where appropriate.

Version persistent data structures.

Projects must not require embedding all original
images.

Handle missing source images gracefully.

## Performance

Never load thousands of full-resolution images
into memory simultaneously.

Use:
- Downsampled thumbnails
- Lazy image loading
- Bounded processing concurrency
- Controlled caching
- Swift structured concurrency
- Cooperative cancellation

Avoid blocking the main thread.

Optimise for Apple silicon.

Respect the tighter memory and execution limits
on iPhone and iPad.

Do not assume iOS processing continues indefinitely
after the app enters the background.

Preserve completed results and support safe recovery
or retry of interrupted jobs.

## Interface

Use native SwiftUI.

macOS:
- Sidebar
- Thumbnail grid
- Large preview
- Right inspector
- Menu commands
- Keyboard shortcuts
- Drag and drop

iPad:
- Adaptive sidebar
- Large touch-enabled preview
- Inspector panels
- Drag and drop where supported
- Apple Pencil-compatible interactions

iPhone:
- Image selection
- Batch settings
- Image review
- Individual adjustments
- Export

Do not force the Mac three-column interface
onto iPhone.

Use shared components where they improve consistency.

Platform-native usability takes priority over
maximising UI code reuse.

## Privacy

The application must function completely offline.

Never implement:
- User tracking
- Analytics
- Remote image analysis
- Cloud image storage
- Automatic image uploads
- Advertising SDKs

Do not log image contents or sensitive metadata.

Do not request unnecessary permissions.

Document any framework behaviour that might involve
Apple-managed system services.

## Legal and Licensing

Prefer native Apple frameworks.

Before introducing dependencies:
1. Identify the licence.
2. Verify commercial redistribution rights.
3. Check App Store compatibility.
4. Preserve required notices.
5. Document provenance.

Do not introduce GPL/LGPL components without
explicit review of distribution implications.

Do not copy competitors' artwork or proprietary code.

Use Apple's Standard EULA unless instructed otherwise.

Do not claim secure erasure, complete anonymity or
guaranteed metadata removal without validation.

## Testing

FramepebbleCore must have automated tests.

Test:
- Image dimensions
- Aspect ratios
- Crop geometry
- Orientation
- Compression
- Transparency
- Colour profiles
- Watermark placement
- Export correctness
- Original preservation
- Cancellation
- File collisions
- Corrupted inputs
- Missing source files

Test shared processing logic independently of the UI.

Both macOS and iOS targets must compile.

Use iOS Simulator testing when available.

Do not assume simulator success proves functionality
on physical devices.

## Build Quality

Keep the project buildable throughout development.

Implement real functionality.

Do not create fake processing results.

Do not silently swallow errors.

Avoid force-unwrapping untrusted image data.

Use meaningful error types.

Document significant architectural decisions.

Avoid unnecessary dependencies and abstractions.

## Development Workflow

Before implementing a substantial feature:

1. Inspect relevant existing code.
2. Identify affected shared and platform-specific modules.
3. Determine regression risks.
4. Implement the feature.
5. Add appropriate tests.
6. Build macOS.
7. Build iOS.
8. Run relevant tests.
9. Report outcomes.

Do not commit or push without approval.

Do not describe incomplete functionality as complete.

## Development Priority

Phase 1:
- Cross-platform architecture
- macOS and iOS application targets
- Image import
- Thumbnail browsing
- Image preview
- Resize
- Crop
- Rotate
- JPEG/PNG conversion
- Export

Phase 2:
- Compression
- Additional formats
- Individual image overrides
- Canvas padding
- Saved presets

Phase 3:
- Vision-based auto-framing
- Subject-aware cropping
- Framing review

Phase 4:
- Text watermarking
- Image watermarking
- Advanced export profiles

Phase 5:
- Performance optimisation
- Project persistence
- Accessibility
- App Store preparation

Both platforms must remain buildable throughout.

## Definition of Done

A feature is complete only when:

- It performs real processing.
- It works within the shared architecture.
- Its applicable platform interfaces work.
- Relevant tests pass.
- Originals remain protected.
- Errors are handled.
- Documentation is accurate.

Production-quality engineering is required.

## Consolidated product direction (14 October 2026)

The user's latest master instructions supersede the earlier phase ordering. Build incrementally:
1. Foundation (existing).
2. Visual framing: Browse/Frame/Compare, fixed-frame thumbnail manipulation, shared precision editing state, selection, overrides, history and review.
3. Intelligence: native Vision framing/classification, actual classification-backed search and reliable centred fallbacks.
4. Output: watermarking, compression, capability-validated native formats, canvas, profiles and metadata.
5. Polish: persistence, accessibility, performance, documentation and distribution validation.

Use the supplied concepts as inspiration: photography-first layouts, restrained blue/violet accents, generous spacing, native controls and adaptive iPhone/iPad workflows. Do not add decorative unfinished controls. Preserve existing edits across selection, mode switches, imports and batch quality changes. Never replace manual overrides during automatic framing unless explicitly requested. Search labels must originate in real local Vision observations; classification confidence must not stand in for object location. Keep output geometry and watermark rendering shared. Test meaningful state transitions and preserve originals. Document actual limitations and physical-device verification gaps. The provisional bundle IDs remain unchanged until distribution is authorised; universal purchase needs a shared bundle ID under Apple's current requirements. Never create App Store records, commit or push without approval.

## Everyday photo toolbox direction

The latest user instructions extend this repository rather than recreating it. Product tagline: Your photos. Your way. Studio remains cross-platform; Automations is a Mac platform adapter using the same Core engine. Priorities are everyday adjustments/sharing, creative collages/annotations, privacy masking, safe folder automation, then integration/accessibility/distribution. Keep ordinary workflows contextual. Never transmit source images automatically. Review-required automation jobs must not publish before explicit approval. No sensitive-content classification is fabricated; unsigned builds use manual review. Private mode is not encryption or secure deletion. Final mask exports are flattened and omit copied supported source metadata. Persistent projects are schema 4 with schema-2/3 migration preserving effective output. Release targets share the universal-purchase identity, while Debug IDs retain development containers. Do not register, submit, accept developer agreements, commit or push without approval.

## Explicit browser imports (user-authorised extension)

The user authorised direct browser image drops on Mac. Prefer supplied image data; only explicitly dropped HTTPS image addresses may be downloaded through the Mac acquisition adapter. No uploads, cookies, saved credentials, developer proxy, tracking or automatic URL fetches. Keep Core local-only and preserve offline file import/editing. Bound downloads, validate actual image bytes, support cancellation and accurately describe website requests in the policy. Mac now requires the network-client entitlement for this acquisition path.

## Workflow and scoped-edit contract

Batch Edit, Photo Editor, Collages and Mac Automations share sources and the processing engine but have distinct action targets. Inspector updates must name fields, preserve other edits and keep inheritance. Schema 4 uses sparse ConfigurationPatch overrides and migrates legacy snapshots without changing effective output. Per-photo framing passes target IDs without changing batch scope. ShareOutputSession contains only successful outputs from one requested operation, never completedOutputs history. Use plannedRequests/exportConfiguration for both profile previews and output; encoded previews must share the export encoder/target-size path. Test actual native modifier gestures as well as selection models.


## Library and tabbed editor navigation

Editor is the user-facing name of the single-photo workflow. Mac uses compact closable photo tabs. iPhone and iPad edit one photo at a time with a visible Back to Workspace action; do not present document tabs or an Open Photos switcher on mobile. Preserve existing stored navigation IDs for project compatibility. Tabs are separate from gallery focus and batch selection. Closing tabs retains project edits and sources. Optional schema-4 tab IDs restore without changing legacy effective output. Privacy is an Editor tool; Privacy Review is a gallery filter. Never change tabs while a privacy/annotation draft is active.


## Product rename

User-facing product name: Ameluma Photo. iOS/iPadOS home-screen name: Ameluma. Retain existing bundle identifiers, internal FramepebbleCore module and legacy storage locations to preserve signing and project compatibility. Do not rename storage paths without a tested migration.


## Multiple collage compositions

Collage tabs have separate source placements and session Undo/Redo, share the photo library, and close without deleting SavedCollage records. Optional schema-4 fields migrate the legacy single collage. Core collage paths/layouts/matching must remain shared. Art generation is local, cancellable and commits only complete, non-stale results. Do not promise perfect reference likeness, uniform tile geometry in shape/text art, arbitrary font/emoji silhouettes or physical-device scale validation that has not occurred. Share only the active composition’s successful captured export.
