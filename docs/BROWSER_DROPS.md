# Browser drops and responsive file imports

## Mac browser drops

Drag the actual image from a browser onto Studio. Framepebble prefers browser-provided image bytes. If only an HTTPS image address is supplied, it downloads that address with an ephemeral URLSession, without browser cookies, stored credentials, a persistent cache or developer-operated proxy. Downloads are limited to 25 MB and five HTTPS redirects, with request/resource timeouts. Actual image bytes are validated through ImageIO, rather than trusting the URL suffix or MIME type.

HTTP-only addresses, page links, inaccessible images, blob URLs and sites needing browser login can fail; save the image in the browser and drag the resulting local file instead. Finder files and recursive folders still work. Browser payload/provider compatibility varies; the native browser-to-app gesture could not be automated because the computer-use service is unavailable. Data providers, URL requests, invalid/oversize responses, folder imports and cancellation have automated coverage. iOS keeps its existing file-drop/PhotosPicker import interfaces.

The Mac client-network entitlement is required for explicit URL acquisition. Processing stays local, with no uploads, analytics, remote analysis or automatic retrieval of project/source URLs. Core still rejects remote image/project URLs. The bundled privacy policy explains the network request/IP-address implications. Earlier review statements that Framepebble had no network client are superseded by this user-authorised feature.

## NAS and large-folder imports

Previously the workspace inspected and hashed each network source before copying it, and import/preview work shared a serial ImageProcessor. Folder enumeration also collected all candidates before displaying them. This delayed first results and could hold up previews behind a slow NAS.

SourceImporter now has a separate acquisition actor:

1. Enumerate lazily, outside the main actor, without accumulating the full folder list.
2. Copy one image at a time in 1 MiB chunks, updating SHA-256 during that same source read.
3. Check source size/modification information before and after copying; reject changed inputs.
4. Decode/validate the local snapshot through the existing engine.
5. Send the completed asset to Workspace immediately. Duplicate hashes are compared locally; owned duplicate snapshots are removed.
6. Lazy thumbnail/preview tasks render from local snapshots on a separate actor while acquisition continues. Existing settings, selected-image identity and framing overrides remain intact.

The pinned Mac progress strip remains below the grid with the inspector hidden. It shows current-file byte progress plus imported/skipped/failed counts. Directory discovery has no known final image count, so it uses discovery feedback instead of a fabricated overall percentage. iOS/iPad show the shared progress component under the collection. Additional file-import requests queue behind active acquisition. Cancellation retains completed images and edits, removes owned partial copies and cancels queued work from the interrupted session. OS-level blocked NAS reads may take time to return; cancellation is cooperative between chunks.

Vision classification is deferred until acquisition finishes so previews and editing receive priority. A new image can be cropped or reframed before its classification becomes searchable. Imported files up to 512 MB are supported, subject to the existing decoded-image pixel limit. Symlink snapshots remain independent; recursive imports skip the app's destination folder to prevent importing newly generated snapshots.

## Validation

The shared tests hold acquisition after its first completed asset and render a thumbnail before releasing the rest, proving the queues are independent. Workspace tests edit the first of 50 images before folder import completes and verify the override survives. Other tests cover chunk progress, source changes, duplicate counts, partial failure cleanup, cancellation, symlinks and recursive-loop prevention. NAS throughput and disconnect behavior have not been measured against the user's homeNAS; physical server/network speed remains a practical limit.

Mac file panels now use nonblocking presentation. Automated Mac test hosts display a test-only view instead of restoring the normal user workspace, so interactive editing is not mixed with test fixtures.

Final verification for this change: 62 shared package tests, 84 iOS Simulator tests and 18 Mac tests passed; both app targets built. The updated Mac Debug app was launched and its restored Studio window was captured in [the launch screenshot](screenshots/mac-browser-network-import.png). Browser gestures and real homeNAS throughput remain user/device QA.
