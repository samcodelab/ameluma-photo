# Privacy design

Framepebble, by Broad Frame Studio, processes images locally using Apple frameworks. The implementation has no account service, analytics, advertising, telemetry, remote inference or third-party runtime dependencies. Image contents and private metadata are not logged by the app.

Imported files are copied unchanged into local Application Support. The local session references those copies and stores editing settings, classification labels, framing proposals, favourites, presets and export recovery state. This data is not uploaded by Framepebble. The current development build has no in-app storage-cleanup interface; removing the app or its support directory removes the local session according to platform behavior. No secure-erasure guarantee is made.

PhotosPicker gives the app only selected items. Saving requests Photos add-only authorization. Native Files panels grant access to selected files/folders. Security scopes are released after import/export work. A future persistent destination system must use platform adapters, not assume unrestricted filesystem or Photos access.

Apple-managed Photos/Files/Share services may download iCloud-only items, synchronize explicitly selected destinations or share with a user-chosen app. Vision uses native on-device requests, and the app downloads no model. These system services and the user's OS settings are outside Framepebble's control. Locally available sources and local destinations can be processed offline.

Supported metadata dictionaries can be preserved, omitted or have the GPS dictionary excluded. This does not guarantee that every location hint, embedded maker note or identifying feature in the image is removed. No complete anonymity or universal metadata-removal claim is made.

This describes the development implementation. Publish a reviewed policy and complete App Store privacy disclosures/manifest assessment before distribution. Use Apple's Standard EULA unless instructed otherwise.

## New tools and automation

Masks and annotations are project edits; final images encode their rendered pixels, not editable overlays or embedded original photographs. Masked exports omit copied supported source metadata dictionaries even if preservation was selected. ImageIO may create new descriptive metadata. Cropping/opaque covers are preferable for stronger concealment; blur/pixelation/frosted effects and metadata policies are not guarantees of anonymity.

Manual sharing approvals/exclusions live only in memory and are reset for a new review session. No sensitive-content classifications are generated or persisted by this unsigned build. Apple's SensitiveContentAnalysis requires a signed entitlement and applicable system policy/developer terms; it has not been enabled or represented as a working detector.

Private Editing Mode bypasses the app's memory thumbnail cache and can conceal the workspace. No persistent thumbnail cache exists. Intentionally saved sources, project instructions and completed outputs remain for recovery. The feature is not a vault, encryption or secure deletion. OS screenshots, backups, Photos/Files caching and cloud-managed locations are outside app control.

Mac Automations access only selected folders through security-scoped bookmarks. Input photographs are unchanged; private snapshots support review/retry. Review/privacy-review jobs are held until explicit approval; automatic jobs export to the user-selected destination. FSEvents/reconciliation operate locally. Content hashes and processing history stay local. No notification contains a private filename. Quitting stops monitoring. Workflow deletion does not delete incoming originals or completed output files; orphaned owned snapshots may require later cleanup.

A project instruction file includes source references, filenames and reversible edits. It is not a flattened privacy-safe image. Use processed-image sharing when concealment is required. Recent projects display names rather than thumbnails. PrivacyInfo.xcprivacy declares no collected/tracking data and file-timestamp reasons for app-owned and user-authorised files; signed distribution still needs a complete API/privacy report review.

Privacy restrictions and authored masks are retained across export profiles. Crop to Hide also omits copied supported source metadata. A framing reset preserves masks/annotations; explicit Reset All is separately labelled and undoable. Source URI boundaries reject non-file image/project/watermark references. Exclusive staging creation never cleans up a pre-existing collision. These safeguards do not certify that a manually drawn mask still covers the intended content after changing aspect/framing; inspect the final output.

The app now displays the bundled policy in Help & Privacy. The reviewed publishing source is [Resources/Legal/PrivacyPolicy.md](../Resources/Legal/PrivacyPolicy.md). Public links are configured in Resources/Distribution.plist; they remain unconfigured until real pages are available. This is a submission blocker.

## Explicit browser imports

Mac now has a user-initiated HTTPS downloader solely for dropped image addresses when image bytes are unavailable. The target site receives a request/IP address and the dragged URL; no browser cookies, stored credentials, local images, developer proxy or telemetry are sent. The 25 MB streamed limit, timeouts, HTTPS-only redirects and cancellation apply. This supersedes earlier statements that the application has no networking client. The bundled policy explains this acquisition separately from local processing.
