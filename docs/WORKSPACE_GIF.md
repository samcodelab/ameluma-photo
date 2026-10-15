# Workspace and GIF implementation

## Initial architectural review

The MainActor Workspace coordinator owns one source array, explicit selection, editor tabs, batch scopes and saved collages. Platform adapters supply Files/Finder/Photos import and native sharing. ImageProcessor imports private snapshots, downsamples previews, renders shared configurations and validates staged exports. AnnotationRenderer and normalised Annotation geometry are reusable. ProjectDocument schema 4 supports optional additive fields with legacy migration.

Found issues: reconcileVisibleSelection intersected selection with filtered IDs; selected batch targets also used filtered assets. Context menus mostly targeted explicit IDs but had no common group action capture. Selection must intersect existing sources only; workflow operations capture ordered IDs independently of subsequent filters or selection. No second library or selection model is needed.

GIF projects use frame-specific captured processing configurations and source IDs, stable frame IDs, centisecond timing and explicit annotation frame membership. The existing source relink UI repairs missing references. GIF rendering reuses ImageProcessor with bounded source decode and AnnotationRenderer. Image I/O handles native palette encoding; no external codec is introduced. Preview uses the same frame composer and timing as export, with reduced resolution.

## Validation

Baseline Core tests and both platform builds are run before implementation. Final evidence and limitations are recorded below as checks finish.

Baseline: 104 Core tests passed; Mac arm64 and generic iOS Simulator targets built unsigned successfully. Initial restricted attempts could not write compiler/Xcode caches; rerunning with approved cache access succeeded.
