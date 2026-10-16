# Workspace and creation reliability review

Review baseline: `a41a4a9`. The checkout was clean and had no subsequent commits when this work began. Repository instructions were read before implementation. The changes below remain uncommitted; signing, bundle identities, internal modules/storage paths, dependencies and distribution records are unchanged.

## Verified findings and changes

| Area | Confirmed finding | Implemented correction |
| --- | --- | --- |
| Source ownership | Workspace removal deleted the only source record while creations retained its UUID. | One canonical `assets` registry remains. Optional schema-4 `hiddenSourceIDs` separates workspace membership from project ownership. Rendering uses the registry; ordinary workspace targets use `workspaceAssets`. Source records survive removal while current/saved creations or session histories require them. |
| Cleanup | Source and watermark dependencies must outlive visibility changes. | Free Unused Working Copies scans current instructions, saved project files, captured GIF configurations and watermark Undo/Redo dependencies. Unknown files/symlinks retain existing protections. Unreferenced hidden records can be released. Cleanup excludes active acquisition/processing, and acquisition/session guards prevent old imports entering a newly opened project. Clearing current work and creations is a separately named, confirmed action. |
| Preview freshness | GIF preparation retained an old image, hiding later failure/recovery controls. | A focused preview session owns temporary files, generation and frame identity. Images require matching current inputs/frame immediately, before an async task starts. Superseded results are discarded and removed. Errors identify the failed frame; replacement/relink uses its source identity. Backgrounding/exit/cancellation invalidates preview resources. |
| GIF Fill | Cropping to source aspect and subsequently centring Fill removed normal-zoom pan freedom. | Fill crops the finished source to the destination aspect with shared `CropGeometry`; Fit uses source aspect. Position and zoom are bounded. Preview/export share the same composer, after captured masks/annotations have rendered. |
| Saved GIF access | Saved creations were accessible only from a populated editor. | Empty/nil/last-frame-removed states expose Saved GIFs. Reopening retains frame IDs, timing, captured configurations and annotations. Cancelling a new selection leaves earlier creations accessible. |
| Relinking | Source UUIDs changed pixels without revoking every creation’s review. | Relevant source URLs/render identities change; photo framing/privacy state is invalidated. Current/saved GIFs and collage histories are flagged for framing; captured GIF masks are checked independently of current photo masks. Current sharing approval is revoked; previously exported files remain immutable. Review flags persist and follow frame duplication/removal. |
| Duplicate lifecycle | A process-lifetime digest set disagreed with project ownership and project opening. | The digest cache maps to retained source IDs and rebuilds on startup/open/relink/removal as needed. Reimport restores membership for a retained identical source; unreferenced removal permits a new import. Import Anyway remains explicit and functional. |
| Scope and conversion | Convert opened the existing default Fit output; some plans also showed nominal dimensions instead of effective native sizing. | Conversion captures fixed inputs and opts into native pixel sizing without rewriting photo edits/defaults/presets. Existing crops/orientation/adjustments remain. Also Resize is explicit. Plans and the phone export sheet describe source sizing. Tabs, selection and captured inputs remain separate. Hidden creation inputs keep their effective edits when ordinary batch defaults change. |
| Task entry | GIF used contextual selection while other tool-first entries differed. | Existing contextual selection now has concrete Edit, Batch, Convert, Censor and Collage destinations. Censor/Edit select one photo. Collage addition preserves existing cells/settings. Phone Convert/Censor are discoverable from Home; Mac/iPad have Quick Tasks. Phone batch/format buttons open working settings/export controls rather than repeating selection. One shared gallery provides filtering/search. |

The renderer, safe staged/exclusive publication, sparse configuration patches and operation-only sharing remain in place. No image-management, cloud, mosaic or new editing-tool work was introduced.

## Compatibility and limits

Schema 4 gains optional/defaulted membership, conversion and review fields; schema-2/3/4 instructions still load. Native sizing is opt-in for new conversion operations. Legacy dimensions/presets retain their saved meaning. Source ownership is not a second image library or source registry.

Projects contain local references, not self-contained cross-device packages. Source copies must be transferred/relinked separately when moving work. Sensitive-content analysis depends on signing capability and system policy. GIF review remains manual. GIF presets primarily change dimensions and native palette banding remains possible. Explicit Mac browser-image drops can download HTTPS image bytes; processing remains local. Temporary previews are removed cooperatively; abrupt termination still relies on system temporary-file cleanup. Private mode is not encryption or secure deletion.

Physical-device memory/energy/throughput, Pencil/trackpad interactions and a full VoiceOver audit remain release checks. Current captures are generated from synthetic fixtures; historical screenshots and test counts in earlier audits are not verification of this implementation.

## Verification

Baseline Core: 110 tests passed, including native rendering and Quick Fix. The previously reported rendering failures/Quick Fix exception were not reproduced here. The final shared suite includes additional pixel, timing, cleanup and failure tests. Environment messages are distinguished from failing assertions: native graphics cache/AutoShortcut diagnostics occurred in some successful app runs; tested rendering and inspected captures still produced expected pixels. This does not establish correctness on untested hardware.

Final checks on 16 October 2026 used `CODE_SIGNING_ALLOWED=NO`; no signing configuration was changed.

| Check | Outcome | Fresh evidence |
| --- | --- | --- |
| Core | 114 passed, 0 failures; Quick Fix passed | `/tmp/ameluma-review-core-verified.log` |
| iPhone 17 app-state/native adapter suite | 196 passed, 0 failures | `/tmp/ameluma-review-delivery-phone.log` |
| iPad Pro 11-inch M5 suite | 195 passed, 1 skipped, 0 failures (196 executed) | `/tmp/ameluma-review-complete-ipad.log` |
| Final iPad reliability/layout rerun | 8 passed, 0 failures, including final Censor scope assertions | `/tmp/ameluma-review-final-ui-ipad.log` |
| Mac native adapters/layout suite | 21 passed, 0 failures, including native modifier events | `/tmp/ameluma-review-complete-mac.log` |
| macOS and iOS/iPadOS builds | Debug test builds and unsigned Release builds succeeded | `/tmp/ameluma-review-release-mac-delivery.log`, `/tmp/ameluma-review-release-ios-delivery.log` |
| Release-tool tests | 2 passed | `/tmp/ameluma-review-release-tests-final.log` |
| Artifact static preflight | 27 checks passed, 0 failures; 4 submission blockers | `/tmp/ameluma-review-preflight-final.json` |

The iPad skip was `WorkspaceTests.testPhotosChangeBlockRunsWithoutMainActorIsolation`: add-only Photos permission was not granted in that test flow. It is not reported as a pass. A Simulator launch attempt failed before tests with SpringBoard Busy/RequestDenied; a sequential retry succeeded. Initial native UI automation was delayed, then recovered. Those infrastructure events do not replace app assertions or establish physical-device behaviour.

Static preflight used the actual unsigned Release artifacts at `/tmp/ameluma-review-release-mac/Build/Products/Release/Ameluma Photo.app` and `/tmp/ameluma-review-release-ios/Build/Products/Release-iphonesimulator/Ameluma.app`. The remaining submission blockers are independently verified public PrivacyPolicyURL and SupportURL pages, and distribution signature/team verification for both platforms. No distribution changes were authorised or attempted.

Live UI checks used synthetic sources and isolated project roots, preserving the personal workspace. On Mac, a missing second GIF frame showed its own recovery actions while the first frame was active; replacement, Undo and Redo switched failure/playback availability correctly. On iPhone, tool-first Convert selected an explicit input, opened Format & Export, and produced an encoded preview of **320 × 160 pixels** from the 320 × 160 source. Censor selected exactly one input and opened the existing reversible Privacy editor. Native draft cancellation was not confirmed after user focus changed; model cancellation/scope tests passed. iPad app-hosted layout tests generated fresh captures; this was not a complete manual iPad gesture audit.

Fresh synthetic captures (local, intentionally ignored by Git): [native-size conversion](screenshots/reliability-convert.png), [large-text selection](screenshots/reliability-selection-large-text.png), [failed-frame recovery](screenshots/reliability-missing-frame.png), [empty saved-GIF access](screenshots/reliability-empty-gif.png). The inspected accessibility-size layout keeps Cancel and Convert visible, although the secondary hidden-selection sentence truncates at this extreme size. Full VoiceOver, physical-device performance, Photos permission paths, Pencil/trackpad and device export/share verification remain required. No historical screenshots or old test counts are used as current evidence.

Regression coverage exercises retained-source rendering/export/save/reopen/cleanup for GIFs and collages, watermark dependencies, source preservation, duplicate lifecycle, acquisition/project-switch races, relinking captured masks and saved creations, preview supersession/cancellation/resources, operation scope, native conversion geometry and representative rendered pixels. Existing collision/publication tests also passed. Tests do not establish uninterrupted background execution or safe recovery from every possible process termination.

