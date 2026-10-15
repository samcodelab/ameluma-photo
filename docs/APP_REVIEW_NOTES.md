# Draft App Review notes

Do not paste these notes as a completion claim until the exact signed submission build has passed the review audit gates. Add real reviewer contact details and public support/privacy URLs in App Store Connect.

Framepebble is a native local photo utility by Broad Frame Studio. There is no login, developer backend, advertising or subscription. Mac, iPhone and iPad use a common Release bundle identity for the intended paid universal purchase.

## Suggested review paths

1. On iPhone, choose Resize or Convert, select photos through the native picker or Files, choose dimensions/format and export new copies. On Mac/iPad, Import leads into Studio. Imported originals remain unchanged.
2. Choose Perfect a Photo or the Adjust tool; use sliders/Quick Fix, rotate and refine framing. Frame thumbnails and precision controls share crop geometry. Apply To specifies current/selected/all/search-result scope.
3. Make a Collage offers grid, magazine and freeform layouts. Select cells to reposition photos, change sources and add titles/captions. Render produces a validated new PNG.
4. Hide Something lets the user draw covers or other masks. Rendered exports are flattened; stronger concealment is provided by opaque covers/cropping. Manual review previews are concealed until revealed. Include/exclude images, approve, then share/save. No automatic sensitive-content detector or guarantee of safety is provided.
5. Mac Automations: choose separate input/output folders, configure enabled actions, choose Automatic or Review Before Export, enable and add an image. A stable transfer must be observed before processing. Review jobs wait for approval. Monitoring runs only while the application is open; the menu bar can reopen Studio or pause workflows. No login item/daemon is installed.

Photos import uses selected-item access; saving asks for add-only permission when invoked. User-selected Apple Photos/Files/share destinations may synchronise according to system settings. On Mac, explicitly dropping an HTTPS image address downloads it when the browser provides no image bytes. This uses an ephemeral session without cookies, stored credentials, a developer proxy or image uploads. Other image processing remains local.

Help & Privacy is available from iPhone home, the workspace sidebar and the Mac Help menu. It includes offline policy and usage guidance; published links must be configured before submission.

Search uses actual on-device Vision labels, not unrestricted natural language. Auto-frame offers useful proposals with deterministic fallback and review flags; it can make mistakes. Live Photos export as ordinary still images. Native format options depend on encoder support. Existing files receive collision-safe output names; originals are never overwritten.
