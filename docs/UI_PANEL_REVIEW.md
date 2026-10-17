# Ameluma Photo interface review and action plan

Ameluma needs a substantial interface pass before more features. Its processing and state models support useful tasks, but the interface exposes too many of those models simultaneously. Navigation, tool selection, operation scope, editing properties, export settings and project housekeeping compete for the same panels. Users must learn the implementation's distinctions before they can confidently edit a photo.

The priority is to simplify that structure, give the photo more room, and establish consistent panel behaviour across tools. Changing colours or replacing long labels with icons will help only after those decisions are made.

Review date: 16 October 2026. Source baseline: `02078d3`. This is a review and proposed implementation plan; application code has not been changed for this audit. The earlier [UI completion audit](UI_UX_COMPLETION_AUDIT.md) and its 9/10 self-assessment do not establish current usability. Passing rendering and state tests is necessary but does not show that users understand the interface.

Open the accompanying [visual comparison board](UI_PANEL_COMPARISON.html) for side-by-side screenshots and proposed panel diagrams. Proposed diagrams show information hierarchy, not finished artwork or implemented interfaces.

## Evidence and boundaries

The review uses native SwiftUI captures from the immediately preceding reliability work, current source, and a live walkthrough of the latest Debug Mac build using an isolated synthetic project. The 14 Mac attachments cover workspace, editor, crop, annotation, batch, history, GIF, errors, contextual selection and collage. The phone and iPad result bundles each contain 19 attachments, including compact and accessibility sizes. Representative captures were inspected directly; the complete attachment inventory is in `screenshots/panel-review/manifest.json`.

Mac captures include 1280 × 820 and 1040 × 700 point content areas. Phone fixtures use 390 × 844 points; iPad component fixtures include 1024 × 768 and 600 × 900. The test hosts use synthetic images and prescribed states. They omit some native window/navigation chrome, so they are evidence about their rendered components, not full-device screen measurements. The live Mac walkthrough confirmed the full shell, clipped inspector tool selector, repeated scope text and duplicate export plan in the current build. No edits to the personal photo workspace were made.

Competitor comparisons use public vendor screenshots and current official documentation, retrieved for this review. They demonstrate design patterns, not measured task completion or feature parity. No competitor binaries were installed, no paid workflows were tested, and screenshot dates/versions can differ. Screenshots with different image aspects cannot support claims that one app always displays larger photos.

All screenshots remain local in the repository's intentionally ignored `docs/screenshots/` area. The visual board is self-contained and includes the selected evidence, with attribution. No source photographs were uploaded.

## Principal findings

1. **The application has several competing navigation systems.** Sidebar Tools, Quick Tasks, editor tool buttons, inspector segments, gallery modes and overflow menus partly overlap. The user has to decide which kind of action each control represents.
2. **Panels do not consistently answer what is being edited.** Photo, batch, frame, composition and export settings share visual treatment. Repeating scope sentences does not create a clear hierarchy.
3. **The controls often consume space before showing useful content.** Large grouped Form sections, duplicate headings and output summaries push adjustments and creation previews down the screen.
4. **iPhone creation tools are largely vertical desktop forms.** GIF and collage controls scroll with the preview; people can lose the image while changing it or have to scroll to export.
5. **The layout rules differ between tools.** Photo settings use Form, crop uses centred stacks, annotation uses a tool rail and custom inspector, GIF uses another stack, and collage nests fixed-height controls inside an outer scroll view.
6. **The existing visual tests have a weak usability threshold.** A capture can pass because some photo pixels are visible while its headers dominate the screen or a tool label is clipped. The review should be driven by task success and readable controls.

## Comparison with familiar tools

| Reference | Visible pattern | Useful direction for Ameluma | Boundary |
| --- | --- | --- | --- |
| [Acorn workspace](https://flyingmeat.com/acorn/docs/acorn_s_workspace.html) | Narrow icon tool palette, large central canvas, selected-tool options in the right inspector; size and zoom in a low status bar. | Move frequent mechanical actions into compact groups; let the inspector explain only the selected tool. | Its many painting tools and layer model exceed Ameluma's needs. Do not copy them. |
| [Pixelmator Pro Mac interface](https://support.apple.com/en-ca/guide/pixelmator-pro/pix96e754af4/mac) | Document tabs, functional tool sidebar, tool-specific pane and optional information bar have separate jobs. | Give each region one job. Keep document switching distinct from tool choice and processing scope. | A familiar pattern does not justify adding layers, professional controls or an enormous icon rail. |
| [Pixelmator Pro iPad tool pane](https://support.apple.com/en-afri/guide/pixelmator-pro/qoyvl9wqyr38/ipados) and [official screenshot](https://support.apple.com/guide/pixelmator-pro-ipad/welcome/ipados) | Compact tool icons and a contextual pane over a substantial image surface. | On iPad, reveal one inspector with an obvious dismissal control. Keep the image and active controls together. | Overlay panels can obscure content; Ameluma must handle portrait, Split View and accessibility sizes deliberately. |
| [Photos on iPhone](https://support.apple.com/guide/iphone/edit-photos-and-videos-iphb08064d57/ios) | Image above a focused adjustment region; familiar Undo and comparison actions; a clear completion path. | Keep the current parameter near the image and distinguish selecting a tool from editing its value. | Photos has its own edit-session semantics. Do not add a fake Done/Cancel transaction over Ameluma's immediately persisted adjustments. |
| [Lightroom mobile workspace](https://helpx.adobe.com/lightroom/mobile/get-started/workspace-overview.html) | Browsing changes to a photo-focused detail view; tool categories sit near the bottom and secondary actions live in menus. | Separate browsing from editing, keep related editing controls in a consistent bottom region, and keep navigation compact. | Its library, cloud, accounts and professional features are outside Ameluma's direction. The reference also has substantial aspect-fit margins; blank space alone is not proof of bad design. |

The strongest shared lesson is **one active context and one relevant set of controls**. Apple also recommends deliberate toolbar grouping and familiar symbols, while retaining text when it communicates an action more clearly. See [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) and [Menus](https://developer.apple.com/design/human-interface-guidelines/menus).

## Space and hierarchy audit

The fixed Mac sidebar is 220 points and the default inspector is 350 points, with an additional 5-point resize divider and the sidebar separator. At 1040 points, these reserve approximately 55% of the width, leaving about 465 points for central content. At 1280 points, they reserve approximately 45%. This is a calculation from the current layout, not a measurement of the photograph itself. Controls and padding then consume some of the remaining region. Widening the inspector to its 470-point maximum makes the narrow-window problem worse.

In the 1040 × 700 editor fixture, a permanent export footer takes roughly the bottom fifth of the inspector, while inheritance text and two Adjust headings consume its upper portion. Only a small number of sliders remain visible. The full native Mac conversion view also repeats `ExportPlanView` inside the settings form and beneath it. The source confirms two render locations; this is not a screenshot artefact.

The phone collage capture starts the composition image at about 58% of the captured height. Above it are document controls, creation cards, a composition/output sentence, Add Photos, layout family, actions, layout name and two preview commands. The photo-first task has become a controls-first page. The phone workspace similarly spends roughly its first third on heading, actions, summary, instruction and filters before thumbnails begin.

The photo editor's blank margins need a more careful treatment. A portrait image in a landscape workspace and a landscape image in a tall phone viewport naturally leave margins. Preserve aspect ratio. Recover space by reducing navigation duplication and making inspector/sidebar visibility adaptive, not by cropping the preview or stretching the image to fill the screen.

## Findings register

Priority **P1** means address in the first structural interface pass because it affects task clarity, discoverability or essential space. **P2** means follow after that structure is established. **V** means verified in a current native capture or live UI as well as source. **S** means source-confirmed placement or interaction concern requiring additional dedicated capture/usability validation. These are design priorities, not a claim that each item is a functional defect.

### Navigation and operation context

| ID | Priority | Evidence | Finding and user consequence | Proposed correction |
| --- | --- | --- | --- | --- |
| 01 | P1 | V, Mac workspace and live shell | Sidebar Tools and Quick Tasks offer parallel routes such as Editor / Choose Photos to Edit and Batch Edit / Choose Batch Inputs. The distinction is about resuming versus choosing inputs but is not stated. Long Quick Task labels truncate. | One stable tool entry per task. Its landing state offers Continue or Choose Photos when needed. Keep contextual Actions for the photo-first route. |
| 02 | P1 | V, Mac batch and phone Convert | Scope is expressed repeatedly as saved inputs, selected images, batch input badges and counts. During Convert, `0 selected` can coexist with one captured batch input. State is correct, but the story appears contradictory. | Use one operation header: `Convert · 1 photo` and `Change Photos`. Gallery selection count appears only while actively selecting; browsing another selection must not imply changed operation inputs. |
| 03 | P1 | V, Mac editor and iPad editor | Filename appears in tabs, photo navigation and inspector header. Adjust is repeated as a tool and two panel headings. | Keep filename in the active tab/title and a compact target chip in the inspector. One tool heading; remove repeated section labels. |
| 04 | P1 | V, phone gallery and live Mac | Actions, Photo actions, overflow menus and permanent Edit/Privacy controls divide similar commands. The presence of an active-photo ring with no selected group is visually ambiguous. | One Actions menu with explicit targets. Clearly distinguish focus from selection using a subtle focus indicator and selection checkmarks. Keep Edit as the obvious photo default. |
| 05 | P2 | V/S, sidebar and source | Workspace/gallery, Edit/Editor, Privacy/Censor/Privacy Review and crop/frame language are not consistently separated. `All images` and `Photo overrides (1 groups)` still appear inside controls. | Adopt the vocabulary below and audit all labels, including grammatical singulars. Do not rename persisted identifiers. |

### Mac panels

| ID | Priority | Evidence | Finding and user consequence | Proposed correction |
| --- | --- | --- | --- | --- |
| 06 | P1 | V, Mac batch and live Convert | Five text segments do not fit the 350-point inspector; the live Mac view clips the first tool, while phone Convert truncates Watermark. Primary tool discovery is compromised. | Remove the inspector's second tool navigator. Use one adaptive tool strip outside the inspector, with icon plus tooltip on Mac and labelled alternatives. |
| 07 | P1 | V, 1040-point editor | Fixed sidebar and inspector squeeze the canvas; sidebar has no ordinary collapse affordance in this custom HStack. | Add a native sidebar toggle, retain resizing, and provide a compact editing configuration. Make width adaptation explicit and reversible. Do not close a user's inspector unexpectedly during a gesture. |
| 08 | P1 | V, editor and live Convert | Detailed output plans occupy the editing footer continuously; Export mode renders the plan twice. | One persistent compact Export action and summary. Detailed filename, profile and destination controls belong in the Export presentation. Preserve the captured operation count. |
| 09 | P1 | V, editor and iPad inspector | iOS-style grouped Form sections create large gaps and repeated cards in a desktop property inspector. Numeric and slider rows consume inconsistent vertical space. | A Mac inspector with aligned property rows and restrained section spacing. Group Light/Colour, Geometry and Output separately. Reuse bindings, not a single panel layout. |
| 10 | P1 | V, crop screenshot | Crop controls are split between toggles above the canvas and a centred right-hand stack. Image scale, position, alignment and action rows lack a shared leading edge. | Put crop properties in the inspector, leaving canvas handles and a compact crop status/action strip on the canvas. Align labels/values consistently; keep precision under a disclosure. |
| 11 | P2 | V, annotation screenshot | Annotation has a different tool rail, selected-state styling, object inspector and Apply/Cancel location. Disabled parent navigation still occupies space during the draft. | Keep the valid draft transaction but use the same tool-strip and inspector geometry. Replace disabled duplicate navigation with a compact draft header. Maintain locked tabs while a draft exists. |
| 12 | P2 | V, Mac screenshots | Brand block, tagline and extra footer tagline consume navigation/status space. Sidebar search duplicates workspace search. | Keep product identity in the window/about/home. One workspace search. Place classifications behind filtering and keep job status in one low status region. |

### iPhone panels

| ID | Priority | Evidence | Finding and user consequence | Proposed correction |
| --- | --- | --- | --- | --- |
| 13 | P1 | V, phone editor | Open Photos, a close control, gallery button/filename row and previous/next row sit above the canvas. App navigation adds another layer in the full shell. | One compact navigation/title row; Open Photos becomes an accessible count button. Put previous/next in a compact optional filmstrip or document switcher rather than a permanent full row. |
| 14 | P1 | V/S, phone adjustment capture and sheet source | Adjust opens a scrolling settings sheet with explanatory scope cards and an embedded preview; a user can scroll between photo and parameters. | Keep one image surface and show the selected tool's controls in a bottom region. A resizable sheet may host long settings, but its opening detent must leave useful image area. Keyboard and large-text layouts need a separate expanded mode. |
| 15 | P1 | V, phone GIF | Preview, transport, frames, timing, canvas, annotations and Export share one long scroll. Essential output and later tools fall below the initial view. | Persistent compact preview/transport and frame strip, with Timing / Canvas / Text controls in a bounded lower panel. Keep Export in the navigation region. Provide an accessible expanded panel mode. |
| 16 | P1 | V, phone collage | Multiple creation launchers and management rows precede the composition. Editing the current composition feels like returning to a creation menu. | Put creation choices on the empty/new state. In an active collage show composition first; selected cell controls and composition properties occupy a bottom panel. Move New/Rename/Layout browsing to compact navigation or menus. |
| 17 | P1 | V, phone workspace | Header/action/instruction/filter rows dominate a browsing page; filenames truncate in small tiles while favourite buttons occupy significant space. | One navigation row and one search/filter region; a contextual bottom action bar appears during selection. Offer filename display through a grid option and accessible details; keep names available to assistive technology. |
| 18 | P1 | V, largest-text editor and GIF | Huge navigation strings, summary text and frame captions consume the viewport. Existing tests pass if some source pixels remain; they do not establish useful editing. | Use shorter accessible navigation, wrap meaningful labels, move secondary detail into a sheet and support an expanded tool list. Do not cap Dynamic Type or simply shrink fonts. Never leave primary controls clipped. |
| 19 | P2 | V/S, Convert and app shell | Settings, Format & Export, export-sheet settings and preview screens create a chain of presentations; the main Export name differs by workflow. | One clear Export presentation per task with format, size summary, destination and primary Save/Share choices. Keep advanced profiles and encoded proof inside it. Return to the initiating task. |

### iPad panels

| ID | Priority | Evidence | Finding and user consequence | Proposed correction |
| --- | --- | --- | --- | --- |
| 20 | P1 | V/S, 1024-point editor components and app source | A 340-point Form inspector takes a large share of the detail region; repeated header cards dominate its top. Full split-view sidebar can make the remaining canvas narrower still. | One contextual inspector sized to available detail width. Hide/collapse navigation deliberately for editing; use a sheet or popover when simultaneous panes no longer fit. |
| 21 | P1 | S, app and GIF width conditions | Photo inspector uses a 760-point detail threshold; GIF uses 780, and collage has a 760-point fixed composition row. Panel behaviour changes by tool at similar widths. | A documented content-width policy with measured minimum canvas/control widths. Use size-class and available width together. Test exact boundary widths, not only device names. |
| 22 | P2 | V, narrow iPad editor | Mac-like tabs, large action buttons, filename navigation and edit-transfer controls persist in a narrow width. White source padding can dominate a dark surrounding canvas. | Use compact document navigation and a single toolbar at narrower widths. Keep source padding distinguishable from the neutral viewing background; never alter exported padding to fix UI contrast. |
| 23 | P2 | S, annotation and collage source | Selection, drawing, moving frames and reframing photos use different control locations and mode descriptions. Pointer and Pencil discoverability needs direct validation. | Consistent visible active-tool state and contextual actions. Retain touch targets; offer pointer help and keyboard commands. Validate mode switching without losing selection or drafts. |

### Creation and supporting panels

| ID | Priority | Evidence | Finding and user consequence | Proposed correction |
| --- | --- | --- | --- | --- |
| 24 | P1 | V, GIF phone/Mac/iPad | Timing uses three large Apply buttons and a field. A blue active frame sits beside `0 selected`, creating two selection concepts with little explanation. Every frame has a separate Frame menu. | Active frame gets direct duration editing. Explicit Select Frames enables multiselection with its count; Apply to All stays a labelled secondary action. Put duplicate/remove/reorder in one contextual frame menu. Preserve frame identity/history. |
| 25 | P1 | V, GIF and collage | Global canvas/output controls and frame/cell-specific crop settings share an undifferentiated stack. Users cannot easily predict scope from proximity. | Inspector headers switch between `GIF Canvas`, `Frame 2`, `Collage` and `Photo Cell 3`; show their relevant controls only. Keep project versus frame settings visually distinct. |
| 26 | P1 | V/S, collage component and source | Collage embeds 520-point canvas and inspector heights inside an outer scroll view; the isolated desktop fixture leaves large blank areas and cuts off controls. | Make the central editor fill available height with independently scrolling properties. Measure regular and narrow presentations in the actual shell before fixing dimensions. |
| 27 | P2 | V, collage gallery | Saved creations and 74 layouts compete on a single page, separated by instructions and filter rows. Creation management and layout choice are different decisions. | Separate Saved Collages from Choose Layout within the existing presentation. Preview selection first, then clearly labelled Apply or Create. Keep the existing catalogue; add no layouts. |
| 28 | P2 | S, watermark source | Position grid uses 44-point cells everywhere; offsets expose fractions; size, opacity and margin each use separate label/slider blocks. | Keep 44-point touch areas on mobile. Use denser native Mac controls, aligned label/value rows, and human-readable percentage offsets. Show advanced geometry on request. Keep normalised storage unchanged. |
| 29 | P2 | S, Projects and Settings source | Project actions, source cleanup, private mode, import preferences and relinking share one management sheet; some are also in Creative tools. Recovery makes people navigate project housekeeping. | Split presentation into Projects, Source Recovery and Settings sections/destinations using existing state. A frame failure opens a source-specific recovery sheet; advanced storage actions stay separate and clearly destructive. |
| 30 | P1 | V/S, missing-frame capture and review source | Error recovery is now reliable, but the failing frame is not visually emphasised in the strip when another frame is active. Privacy/relink review is text-heavy and distinct from editor navigation. | Mark the affected frame/cell and provide an explicit jump/recovery action. Keep useful safe wording and review requirements; move general explanation into expandable help. Do not replace manual GIF review with a misleading assurance. |
| 31 | P2 | S, Mac Automations source | Monitoring state, publication mode, counters and six actions are repeated within every workflow section. Pending/failure entries expand beneath them. | A compact workflow list with status and one selected workflow detail pane. Make Test, Run and Approve distinct, with publication mode visible. Retain review-before-publication behaviour. |
| 32 | P1 | V/S, tests and historical audit | Captures test bounds and a low photo-pixel threshold. They do not reject clipped primary tools, duplicated output summaries or unnecessarily deep navigation. A previous 9/10 score overstates the evidence. | Add readable-control, scope, navigation and visual review gates. Treat automated screenshots as evidence to inspect, not an automatic usability score. |

## Proposed interface contract

### Give every region one purpose

| Region | Responsibility | Exclude |
| --- | --- | --- |
| App navigation | Workspace, editing/creation tasks, Projects and Mac Automations | Duplicate launch routes and editing properties |
| Document navigation | Current photo/GIF/collage and other open documents | Batch membership changes and creation settings |
| Tool strip | Select the operation used on the current content | Export configuration, project cleanup and unrelated task launchers |
| Context header | Name the exact current target and count; allow deliberate input changes | Repeated scope paragraphs in every section |
| Inspector | Properties of the active tool and target | A second full tool picker and permanent detailed export plan |
| Export presentation | Output format, size, naming, profiles, destination, proof and publication progress | Editing-task navigation and project management |
| Status region | Current job progress, failure/recovery and concise processing state | Branding and persistent tutorial prose |

Keep a short operation statement such as `Batch Edit · 12 photos` visible. A single-photo inspector can show `This photo · 2 overrides` with a disclosure explaining inheritance. Per-field overridden/mixed indicators and explicit reset remain available. Do not simplify the view by changing which objects an operation affects.

### Mac layout

Use a collapsible native navigation sidebar and one flexible canvas. A compact document/tool header sits above the canvas. The contextual inspector starts around 280–320 points as a prototype target, subject to actual control measurement and localisation. Keep it resizable. At a 1040-point window, an editing presentation with navigation collapsed should leave at least 65% of the content width for the canvas region; this is a proposed acceptance target, not an Apple rule or a guarantee of photographic pixel area.

Use one inspector title with leading-aligned sections. Place property labels and numeric values on common baselines; align numeric columns with monospaced digits. Use 8-point spacing between related controls and 16-point section spacing as initial tokens. Mac control heights should follow native control sizes, not 44-point mobile cells. Avoid a new custom docking system.

Export is a consistent toolbar command. A compact optional footer can say `12 photos · JPEG · Export…`; detailed output plans move into Export. Undo/Redo, zoom and compare have compact controls and keyboard shortcuts. They do not need sentence-length permanent buttons.

### iPhone layout

Keep one compact navigation region with Back, task/document title, Undo/Redo or overflow, and Export. A labelled bottom tool strip selects Adjust, Crop, Privacy and other existing tools. The selected tool exposes a focused panel while the image remains visible. Longer settings use a native sheet with appropriate detents and an expanded mode for accessibility text or keyboard entry.

For GIF, keep preview, transport and a horizontal frame strip together; Timing, Canvas and Text select the lower controls. For collage, retain the composition above a context-sensitive panel; selecting a photo reveals its framing/replacement properties. New-creation choices belong before or outside active composition editing.

The first layout target at 390 × 844 points and default text is for stacked navigation and duplicated summaries to consume no more than 20% of usable content height. Provide an aspect-fit image region above the controls. This is a prototype budget: actual device safe areas, image aspect, keyboard and largest text require separate layouts, not a forced universal percentage.

### iPad layout

Wide landscape can display canvas and one inspector. Portrait and multitasking should collapse app navigation first, then present properties in an appropriate sheet/popover when the canvas and inspector cannot both fit. Use the actual detail-region width, not total screen width. Preserve the user's active document, tool, inspector scroll and unfinished draft through transitions.

Use the same conceptual tools as iPhone/Mac, with touch-sized controls and pointer/keyboard help. Do not simply scale down the Mac three-column layout. A 600-point editor needs a deliberate compact document/tool arrangement rather than desktop rows squeezed into the same width.

### Panel contents by task

| Task | Default visible properties | Secondary properties |
| --- | --- | --- |
| Adjust | Auto/Quick Fix, Light and Colour groups; aligned value/slider/reset | Copy chosen edits, advanced framing/style options |
| Crop | Aspect, straighten, rotate/flip, reset; direct canvas handles | Numeric position/zoom, guides, subject proposals and export-size policy |
| Resize | Width/height or chosen resize basis, aspect link, fit/fill and background | Prevent upscaling and advanced canvas styling |
| Convert | Format, quality if applicable, Source Dimensions, Also Resize | Colour, metadata, target-size limits, naming and profiles |
| Privacy | Draw/select, cover effect/shape, selected area properties, Apply/Cancel | Review limitations and precision geometry |
| Annotate | Add text/arrow/shape; selected object's properties, Apply/Cancel | Object list and numeric positioning |
| Watermark | Content, position, size and opacity with direct manipulation | Tiling, rotation, precise offsets, presets |
| GIF | Active frame timing or selected annotation; explicit canvas context | Loop count, order, presets and output details |
| Collage | Layout and spacing at composition scope; crop/replace at cell scope | Existing artistic modes, title, borders and output settings |
| Export | Captured count, format, effective size, filename/destination and Save/Share | Multiple profiles, proof, metadata/colour policies |

Preserve useful disclosure of mixed values, safety failures and metadata behaviour. Put warnings next to the setting they explain. Long generic tutorials can move to contextual help, but source protection and review requirements must remain understandable at the decision point.

## Icons labels and terminology

| Control | Recommended treatment | Reason |
| --- | --- | --- |
| Undo/Redo, Play/Pause, Restart, zoom, rotate/flip, sidebar, close tab | Familiar SF Symbol with accessibility label; Mac tooltip and shortcut | Recognisable mechanical action; little value in repeating full text |
| Primary task tools on iPhone/iPad | Icon plus short label; selected state in shape and text | Discovery matters and touch has no hover |
| Mac tool selector | Compact symbols with tooltip, selected tool title and an accessible labelled menu alternative | Save width without creating an unexplained icon wall |
| Export, Add Photos, Change Photos, Apply/Cancel, Replace, Locate Source | Short verb labels; optional icon | Consequence and destination must be clear |
| Convert, Censor/Privacy, Batch Edit | Keep words in task entry menus | No universally understood symbol distinguishes these tasks |
| Remove from Workspace, Clear Workspace and Creations, delete creation | Explicit labelled actions in contextual menus/dialogs | Icon-only trash would erase the ownership distinction |
| Numeric fields | Short label, value and unit; shared alignment | Width/height, timing and percentages need context |
| Help and inherited-setting explanation | A short visible state plus contextual disclosure | Reduce repetitive text without removing the explanation |

Use **Workspace** for imported working photos; **Edit Photo** as the action and **Editor** as the destination; **Batch Edit** for the captured group; **Crop** as the tool with **Auto-frame** inside it; **Convert** for format conversion; **Privacy** as the editor tool with **Censor a Photo** retained as a plain-language entry if helpful; **Privacy Review** only for reviewing photos/outputs. Use **GIF**, **Frame**, **Collage** and **Photo Cell** for their separate targets. Prefer `3 photos have individual changes` over `Photo overrides (3 groups)` in everyday UI.

Icon changes must not remove scope. A rotate button's visible context and accessibility label must still identify whether it affects this photo or a captured batch. Do not reuse the same icon as both an enabled-looking navigation button and a disabled decorative status indicator.

## Action plan

Proceed in six bounded stages. Estimates are planning ranges for one engineer with design review, not delivery promises; device/localisation findings can change them. Review each stage before propagating its components to every tool.

| Stage | Work and affected areas | Reviewable deliverable | Acceptance gate | Effort |
| --- | --- | --- | --- | --- |
| 1 | Agree navigation, target header, tool grouping and export presentation using `MacWorkspace`, `MobileWorkspace`, `LibraryViews`, `WorkflowViews` and `Inspectors` | Two representative Mac editor states, iPhone editor/Convert, iPad wide/narrow wireframes and the label inventory | A reviewer can identify task, target and next action without reading helper paragraphs. No state-model changes. | 2–3 days |
| 2 | Implement Mac panel structure: sidebar collapse, one tool navigator, aligned property rows, remove duplicate output plan, compact export action | Working Mac Adjust/Crop/Convert at 1040, 1280 and 1440 points | No clipped tool labels at minimum supported width; one export summary; larger canvas region; keyboard/selection/draft semantics unchanged | 3–5 days |
| 3 | Implement phone editing shell and iPad adaptation using the same bindings | Working Adjust/Crop/Privacy/Convert and width transitions | Image and current controls remain usable; essential actions never require hunting through a long settings form; keyboard and large text have deliberate layouts | 4–6 days |
| 4 | Move GIF and collage into the established panel contract; retain existing features | Working frame/cell inspector, compact transport, creation empty states and saved-work access | No lost frame/cell configuration, order, annotations, history or unfinished projects; Export is visible and recovery identifies its target | 3–5 days |
| 5 | Tidy secondary panels, wording and icon consistency: watermark, Projects/Recovery, review, Automations | Inventory with every existing control assigned to a destination; focused recovery screens | No hidden safety action, no misleading icon-only destructive control, no new feature work; existing project/output semantics retained | 2–4 days |
| 6 | Task-based usability sessions, visual regression matrix, native accessibility/device checks and both-platform validation | Before/after captures at identical states and a remaining-issues list | Meet the task and accessibility gates below; review pixels and interactions rather than just test counts | 3–5 days |

Total initial range: **17–28 engineering/design days**, sequentially estimated with review. A useful first implementation slice is Stage 2's **Mac Adjust and Convert panel**, followed immediately by the phone version. These expose the shared hierarchy issues without requiring a whole-app rewrite. Do not spend the first iteration polishing the Home screen while the editing panels remain unresolved.

### Implementation constraints

Reuse `Workspace` operation inputs, sparse field patches, existing creation/history models, renderer and export adapters. Extract focused view components such as a target header, property row and export summary where they genuinely repeat. Share their intent and bindings while allowing platform-specific layout. Do not introduce a generic workflow coordinator, a new source registry, a custom window docking framework or a second photo gallery.

Move controls without changing their processing semantics. The exported dimensions of saved work and presets, protected overlays, captured GIF configurations, Undo/Redo grouping, source ownership, selection across filtering and successful-output sharing all remain regression requirements. A tooltip or summary should describe effective settings, not introduce a new default.

### Required task walkthroughs

| Scenario | Pass condition |
| --- | --- |
| Import and edit one photo | Find Adjust/Crop without help, see the image while making changes, export one photo and return to it |
| Choose Convert first | Select inputs, identify their fixed count, change format and export with source dimensions unless resize is explicitly enabled |
| Select photos first | Find Batch Edit/Convert/GIF/Collage from the same Actions route; filtered hidden selections remain counted |
| Switch editor tabs | Active document changes visibly; batch membership does not change; inherited effects remain understandable |
| Add a privacy cover | Discover Draw/Select, reposition/resize, Apply or Cancel deliberately; never leave a concealed/review-required result silently approved |
| Make a GIF | Add frames, identify active versus multiselected frames, change one/all durations, annotate, export and reopen saved work |
| Edit a collage | See composition immediately, select a cell, reframe/replace it and export only the active composition |
| Recover a missing source | The affected frame/cell/photo is named; Locate and Replace are distinguishable; return to the creation without losing its edits |
| Resize or rotate the device/window | Active tool/target persists and controls reflow without clipping or dismissing a draft |

Run formative sessions with roughly five people who use Photos/Lightroom/Pixelmator or similar tools, including at least two who have never used Ameluma. Observe without teaching the vocabulary. Record wrong turns, backtracking, requests for help and whether they can state the operation scope before export. Five sessions are a practical first round, not statistical proof of usability. Repeat on phone and Mac; validate iPad separately.

### Visual and accessibility gates

Capture the same source aspects, settings and workflow states before and after changes. Include landscape, portrait and square sources, multiple open documents, long filenames, mixed batch values, overlays, missing files, empty/saved creations and export progress/failure. Inspect the real app shell as well as individual components.

Mac widths: 1040, 1280 and 1440, inspector minimum/default/maximum, sidebar visible/collapsed, light/dark and increased contrast. iPhone: at least small and large supported sizes, portrait/landscape, default text and accessibility sizes through the largest. iPad: wide/portrait and multitasking widths around 600, 759/760 and 779/780/781, plus keyboard shown. Width-boundary tests should target the actual post-navigation detail width.

No primary tool or action may be clipped or rely on hover alone. Align property labels and numeric columns consistently. A 44-point touch target need not be a 44-point icon or a giant text label. Preserve Dynamic Type, non-colour selection cues, VoiceOver labels/order, keyboard focus, Escape/Return semantics and Reduce Motion. Test floating keyboard/sheet detents and the accessibility reading order of contextual error actions on devices.

Automated checks should assert that only one detailed Export Plan is rendered, all advertised primary tools remain discoverable, task headers report the correct captured IDs/count and sheet navigation returns to its source. Retain meaningful state/processing tests, run Core and native adapter/app-state suites, and build macOS and iOS/iPadOS after each structural stage. Add screenshots for review, but do not substitute image-existence or photo-pixel assertions for human inspection.

## Delivery status

This audit changes documentation and provides a visual comparison board. It does not implement the proposed UI, claim new usability-test results, rerun the already-passing processing suites as evidence of design quality, or certify accessibility. Physical-device use, full VoiceOver and external keyboard/Pencil/trackpad checks remain part of the proposed work. No commit, push, publication, signing change or competitor asset reuse in the application was performed.

The comparison board was rendered and inspected in Safari. Platform filtering, screenshot enlargement, Escape dismissal with focus return, and switching the proposed-layout tabs were exercised. All 18 embedded screenshots decoded through native Image I/O; local report links, unique element IDs, JavaScript syntax, the 32-item register and `git diff --check` passed. The board requires no network access to display its evidence.
