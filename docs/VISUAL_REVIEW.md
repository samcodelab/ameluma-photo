# Visual review against the supplied concepts

These screenshots show actual development builds and real processed inputs, not marketing mockups:

- [Mac Frame + Precision workspace](screenshots/mac-framing.png)
- [iPhone compact library](screenshots/iphone-library.png)
- [iPhone precision reframing](screenshots/iphone-refine.png)
- [iPhone successful Photos export](screenshots/iphone-export.png)
- [iPad adaptive workspace](screenshots/ipad-workspace.png)

The dog photograph is CC0; see `QA_ASSETS.md`. The Mac capture uses the host's dark appearance and the mobile captures use the Simulator's light appearance. No app networking or stock-image fetching is involved in the displayed UI. The iPad screenshot is an honest empty-library state; no decorative/fake photographs were inserted.

## Concepts reflected in implementation

Native sidebar categories, recognition-backed search, Browse/Frame/Compare modes, blue/violet branding, restrained selection borders, fixed output framing, right-hand precision editing, before/after guides and prominent export actions are implemented. The phone has a compact photo grid, full-screen refinement, separate native settings/export sheets and add-only Photos saving. Crop state is shared with the grid and remains intact when closing/collapsing the editor.

Live checks confirmed thumbnail dragging changes the precision coordinates, numeric zoom updates both surfaces, Undo restores the drag, Smart uses real detections, sessions survive relaunch/container moves, and the full real-photo Photos save finishes successfully. Mac inspector resize/collapse/reopen was exercised after replacing an unstable native split-controller layout with bounded SwiftUI panes.

## Differences and polish opportunities

The concepts are dense promotional collages with many varied photos. QA captures use one real public-domain photo, and no fabricated library counts or AI search results. Current inspectors expose more explicit settings and need further progressive disclosure/density tuning. The brand mark is a small code-rendered blue/violet pebble rather than the concept's sculpted sphere; app-icon production remains a release task. Native current-OS controls include system glass/rounded styling; older supported OS versions may render differently.

The large Mac precision preview lives within a bounded inspector, while the concepts sometimes dedicate most of the centre to a single photograph. Compare mode provides a larger central comparison. iPad uses adaptive native navigation and a side inspector rather than copying the Mac window chrome. Phone controls scroll in precision mode instead of reproducing the exact illustrated bottom toolbar; unimplemented camera/filters/semantic-model features are not shown as functioning buttons.

Next visual work: richer photo-corpus review, selected-thumbnail scroll visibility when navigating, inspector disclosure groups, numeric-field formatting, more compact phone control grouping, desktop drag-out behavior, and accessibility/Pencil/trackpad validation. Framing gestures show the cached source; the full watermark composite returns on gesture completion. This remains a development foundation with real functionality, not final App Store artwork or a release-ready marketing representation.

## Everyday toolbox update

The new phone home gives five task actions and recent-project access, matching the task-oriented direction rather than a desktop inspector. Native light-mode sheets handle privacy drawing and sharing review; dark Mac Studio keeps the photograph/grid central, with contextual Frame/Adjust/Create/Export controls. The sidebar now separates Studio, Create and Mac Automations. Actual captures: `iphone-toolbox-home.png`, `iphone-toolbox-mask.png`, `iphone-toolbox-review.png`, `mac-toolbox-adjust.png` and `mac-toolbox-automation.png`.

Corrected during live QA: a mobile large navigation title overlapped the tool selector; compact native titles now leave the segmented control visible. A review sheet initially captured an empty output array; item-based presentation now shows the exact final file. Approval revocation and reviewed Photos saving were checked in the actual app. Native Mac File/Photo menus and contextual controls improve access to simple rotate/import/export tasks.

These are real development interfaces using the CC0 QA photograph, not promotional renders. Compared with the supplied concepts, the build uses current system styling, fewer decorative elements and explicit scope/metadata/review controls. The screenshots do not simulate a populated multi-subject collection. Remaining polish includes direct resize/rotation handles, typography for long captions, greater preview emphasis on phone, control density, VoiceOver/Dynamic Type audits and diverse-photo interaction testing. Collage templates are a small algorithmic set; refined magazine typography and stacking controls remain opportunities.

The final capture/complete collage interaction check could not be performed: native automation reported `Sky Computer Use native pipe startup failed` after reconnection/reset attempts. Captures above are authentic builds during this extension, but precede some final sidebar/preview/icon refinements. Backend collage tests are not a substitute for that remaining UI acceptance run.
