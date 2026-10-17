# Demo Workspace

Open **Demo Workspace** from the workspace sidebar, Projects, or the iPhone home screen. It opens 30 independent generated photographs in the normal editing tools. A compact **Demo** menu in native navigation identifies the sample session and provides **Return to Your Workspace**. Full-screen draft tools identify the demo in their title; apply or cancel the draft before returning. Demo content is never inserted automatically into a personal workspace. The bird hero leads the seed order, followed by the golden-light and coastal portraits; deliberately imperfect photographs are last.

The original personal `Workspace` instance stays alive with its sources, edits, selection, history and open tabs. Opening the demo checkpoints personal edits first. The active view and Mac menu commands then use the demo model. The Mac status-menu/Automations adapter stays attached to the personal workspace; Automations is omitted from the demo sidebar. Entering or leaving the demo is disabled during active import/export/generation or an overlay draft. Finish that work first.

Demo storage lives below the existing session root in `DemoWorkspace-v1/`, with its own `Session.json`, `Sources`, `Projects` and export working files. Its source copies are independent of bundled assets and personal sources. Demo edits survive leaving/reopening and app relaunch; launch still starts in the personal workspace. All regular import, project and explicit export actions operate on the active workspace. A user can deliberately import personal files into the demo or export demo results to a chosen destination, so the demo label indicates the session, not a security boundary. Project instructions retain file references rather than embedding photos.

The app bundles `Resources/DemoWorkspace` as a folder resource on Mac and iOS. First open validates the manifest and copies/decodes every photograph off the main actor through the existing ImageProcessor. It publishes a session only after all copies succeed; a failed seed removes its partial copies and leaves personal work active. Later opens restore the demo session without replacing edits or silently refilling removed samples. A corrupt or missing-source demo session reports an error rather than silently discarding work. Demo project copies and source cleanup remain within the demo root.

See `Resources/DemoWorkspace/README.md`, `manifest.json` and `generation-prompts.json` for provenance, native dimensions, usage and exact prompts. No network access is used by the running app to load the demo.

## Sizing and interface

Fresh personal workspaces and freshly seeded demo sessions start at 100% source dimensions, using the existing preserve-aspect processing mode. A fixed size preset explicitly chooses a Fit canvas. Existing saved sessions, projects, individual edits and presets keep their effective output; opening them does not silently adopt the new defaults. An existing demo session is also preserved. Use Restore Original Appearance when you explicitly want to discard its visual edits and return to source dimensions.

Mac and landscape iPad display common editing options near the tool rail over the canvas edge. Close the surface when it covers the photo and tap the active tool to reopen it. Detailed settings remain optional. Portrait controls sit above the toolbox. Zoom is in the contextual view menu; draft Undo/Redo remain separate from committed photo history. At accessibility text sizes, draft history and deletion use a labelled menu to keep Apply/Cancel readable.

Batch galleries default to captured Inputs; the visible Inputs/Workspace menu only changes the gallery view. It never changes selection or captured operation membership. The scope menu and caption distinguish operation inputs, workspace count and selected photos. Routine batch badges no longer cover photo content.

## Verification

Current verification evidence is recorded in [the updated comparison report](DEMO_WORKSPACE_FINDINGS_IMPLEMENTED_2026-10-16.html), including fresh native captures, compatibility/rendering tests, exact suite/build results and remaining device checks. Earlier direct-compiler checks and historical screenshot counts are not evidence for this implementation. Earlier rendering/Quick Fix exceptions and the long Mac native capture exception are not declared harmless; the report identifies the current run's scope and exclusions.

The repository contained substantial pre-existing uncommitted work. It was retained. No signing, storage identity, processing-engine architecture, commit, push or publication changes are part of this interface update.

## Landscape hero addition

`27-coastal-hero-landscape.jpg` is a 1536×1024 companion generated from the existing vertical hero using the built-in image tool. The original remains intact. New demo sessions include both portraits. Existing demo sessions receive the new photograph once on their next open, preserving their current document, photo IDs, edits and selections. A per-photo receipt under the demo root prevents duplicates and respects later removal of the sample. Personal workspaces receive no sample assets. The manifest designates the landscape hero and retains the vertical portrait designation.

Landscape-addition verification: all 27 packaged images decoded and matched their recorded hashes. All five focused demo tests passed, including the new legacy-session addition/idempotence/removal test. Mac Swift 6 compilation/linking and iOS Simulator Swift 6 module compilation passed after this change. This earlier direct-compiler result is historical; use the current report above for Xcode and Simulator verification. Physical-device checks remain necessary.

## 17 October interface consolidation

Mac, iPhone and iPad use the same bundled 27-photo manifest and files, including both Coastal Hero portraits. Mobile Start now places **Open Demo Workspace** immediately below the welcome heading. Enter from the sidebar or Projects on iPad/Mac. Demo projects remain local and separate; they are not synchronized across devices. A new native regression loads the manifest from the actual app bundle and opens it through the normal workspace path, rather than falling back to test resources. This passed on Mac; the iOS app builds with the same resource folder, but current Simulator execution is blocked by a CoreSimulator service/build version mismatch. See [the implementation evidence](INTERFACE_CONSOLIDATION_2026-10-17.html).

## Mobile viewport and tool tray

The ordinary photo preview supports transient pinch magnification and double-tap zoom/reset; it never changes crop geometry. Full-resolution inspection is an optional Photo View menu action, with a dedicated Done Inspecting control and separate zoom bar. Filters replace the phone/portrait editing toolbox with a fixed Tools return button and scrolling presets. Accessibility text sizes use a dedicated scrollable Filter Settings presentation. On iOS and iPadOS, drawing drafts put Cancel, Undo, Redo and Apply in the navigation toolbar, keeping the bottom for tool controls. Mac retains its existing draft action footer. Pinch zoom on drawing canvases takes priority over drawing and clears the unfinished gesture path; committed edits remain unchanged. Physical touch/Pencil gesture verification remains required.

## Bird hero and golden-light portrait — 17 October 2026

The collection now contains 29 individual photographs. `28-rainbow-bird-hero.jpg` is the primary hero and first photo in fresh demo sessions. `29-golden-light-portrait.jpg` is a polished lead portrait of a fictional Black woman, placed alongside both retained coastal portraits. Both new images use the built-in image generator without external reference photos. Exact prompts, dimensions and hashes are in the asset manifests. Existing demo sessions receive these additions once on next opening in the updated build, preserving their edits and respecting later removal.

Bird/portrait verification: all 29 originals and both built-app resource collections matched their manifest hashes. The full Xcode macOS build and seven DemoWorkspaceTests passed (zero failures); the iOS Simulator app build also passed. Tests cover real app-bundle loading, original preservation, source-size rendering, demo restoration and one-time additions/removal. Physical-device and App Store checks were not run. Exact prompts are in generation-prompts.json; generated photos do not imply National Geographic publication or endorsement.

## Central lorikeet refinement — 17 October 2026

`30-lorikeet-hero-clean.jpg` replaces the primary hero designation and leads fresh demo sessions and screenshot capture. It centres the bird against a quieter background. The original lorikeet and all portraits remain intact. Existing saved demos receive the new source once on next open in the updated build, without changing their existing edits or original source bytes. The gallery now contains 30 photographs. Exact prompt, generation provenance, dimensions and hashes are recorded alongside the assets.
