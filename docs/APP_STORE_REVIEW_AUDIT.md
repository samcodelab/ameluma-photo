# App Store reviewer audit — 14 October 2026

**Subsequent implementation update:** Browser drops now include explicit HTTPS image downloads on Mac, with a client-network entitlement and revised bundled privacy text. NAS acquisition now publishes images incrementally on a separate actor. Historical counts and the no-network assessment below apply to the earlier audit build; regenerate signed artifacts/preflight for release. See [current import behavior](BROWSER_DROPS.md).

**Decision: hold submission.** Repository fixes and unsigned archives pass their checks. This is not a signed distribution acceptance test, and Apple alone determines approval.

## Reviewer findings

| Area | Finding and disposition |
| --- | --- |
| Privacy policy (5.1.1) | Fixed missing in-app policy/help access on Mac, iPhone and iPad. Policy explains local copies, retention, permissions, user-directed sharing and limits. Public policy/support URLs remain blank at the owner's direction; submission is blocked until working pages are supplied. |
| Mac sandbox / folder workflows (2.4.5) | Added `com.apple.security.files.bookmarks.app-scope` for the existing persisted security-scoped folder bookmarks. Sandbox and user-selected read/write remain enabled; no network or temporary-exception entitlements. Actual signed sandbox/bookmark restoration/revocation still needs testing. |
| Accurate feature presentation (2.3) | Removed unsigned-development language from sharing review. The UI explicitly describes manual review and makes no automatic sensitivity-detection claim. No SensitiveContentAnalysis entitlement is requested. Native codecs are capability-gated; classification search does not promise unrestricted natural-language recognition. |
| Completeness (2.1) | Added Mac menu-bar action to reopen Studio. Phone settings now dismiss before opening framing/creative/project editors. Export/settings transition is sequenced. Tests and compile checks pass; these changed presentation flows require live click-through. |
| Permissions (5.1.1(ii)) | PhotosPicker imports selected items. Only add-only Photos permission is requested for saving. Strengthened purpose text with finished-photo/collage examples. Denial produces user feedback; no camera, microphone, location, full Photos-read or tracking permission. |
| Minimum functionality / design (4.2) | Real native editing, batch processing, collages, masks and Mac workflows exist. No decorative future controls or developer-operated services were found in the inspected app source. Usability, accessibility and physical-device validation are not replaced by this assessment. |
| Original preservation | Shared engine, staged/exclusive publication, validation, collision handling, cancellation, partial-result recovery and mask flattening remain intact. Shared/workspace regression coverage passed. |
| Privacy manifest | Bundled on both platforms, no tracking/collected data declared. Timestamp APIs used for app-owned/user-selected source fingerprints and local reconciliation are covered by C617.1/3B52.1. No direct UserDefaults, disk-space, boot-time or active-keyboard API use was found. Reinspect the final signed archive's Xcode privacy report before upload. |
| Dependency/content provenance | Local shared package only; Apple frameworks. Original generated icon. Public CC0 QA dog photo stays in ignored build data and is not a shipping resource. User concept artwork is not bundled. No accounts or in-app public content service. |
| Business / universal purchase | Both Release targets use `com.broadframestudio.framepebble`. Configure one shared app record. No separate repurchase mechanism, subscription or IAP exists. Price, territories, paid agreement and Standard EULA are owner/store tasks. |
| Signing / SDK | Xcode 27.0 (27A266a), device SDK build and universal Mac Release archive succeed. No valid signing identities are available. Archives are unsigned and cannot be submitted or treated as signed sandbox/device validation. |
| Export compliance | Inspected CryptoKit use is SHA-256 duplicate hashing; no proprietary encryption or encrypted vault. Owner must answer the current questionnaire and set appropriate export-compliance keys after determination. This audit does not make a legal classification. |

## Verification

- iOS Simulator app-hosted suite: 75 passed, zero failures (55 Core, 17 workspace, 3 distribution-resource tests).
- macOS app-hosted suite: 8 passed, zero failures (5 automations, 3 distribution-resource tests).
- Release-preflight URL tests: 2 passed.
- Unsigned iPhone/iPad device-SDK Release archive: succeeds.
- Unsigned Mac Release archive: succeeds; x86_64 and arm64 slices verified.
- [Final archive preflight](APP_STORE_PREFLIGHT.json): 27 static checks pass, no artifact failures. Strict mode deliberately fails on absent policy/support URLs and unverified Mac/iOS distribution signatures.
- Native computer-use tool still fails with `Sky Computer Use native pipe startup failed`; new help navigation and presentation flows could not be clicked through. No physical-device validation is claimed.

Normal AppIntents extraction warns that no AppIntents dependency exists. Tests also show Apple's linkd service connection diagnostics; no test failure resulted. These are not evidence of app telemetry or required AppIntents functionality.

## Required before submission

1. Publish reviewed privacy/support pages with Broad Frame Studio contact details. Set `Resources/Distribution.plist`, rebuild and verify both the in-app links and live pages. Owner confirmed pages are not ready; no URLs were invented or published.
2. Configure an authorised developer team/certificates/profiles and the shared app record. Produce distribution-signed archives; run Organizer validation and inspect signatures/entitlements/privacy report. No account records or agreements were changed here.
3. Run clean-install and upgrade tests on signed Mac, iPhone and iPad builds, including macOS 15/iOS 18 compatibility. Verify every advertised workflow, sheet transition, menu-bar reopening, denied Photos access, Files providers, bookmarks across restart/revocation, Photos-compatible formats, termination recovery and cancellation.
4. Exercise VoiceOver, Dynamic Type, landscape/iPad multitasking, pointer/keyboard, light/dark mode and large real-world batches. Check peak memory on high-resolution photographs. Shared geometry tests are not a substitute for these checks.
5. Complete accurate App Store descriptions/screenshots, review contact details, app privacy responses, age-rating questionnaire, territories/trader status where applicable, copyright, export compliance, price and Standard EULA. Do not advertise automatic sensitive-content detection, a vault, secure erasure, universal metadata removal, guaranteed auto-framing, arbitrary semantic search or unsupported codecs.
6. Retest the exact signed build to be submitted. Attach review instructions that match that build. Run strict preflight and store validation; only then request approval to submit.

## Modified files

App entry points, Workspace presentation state, shared inspector routing and sharing-review text; new HelpPrivacyView; sandbox entitlements; bundled policy/help/distribution configuration; Xcode generator/project; distribution-resource tests; release preflight and URL tests; this audit and review notes. Image transformation algorithms were not changed.

## Reproduce the archive preflight

```sh
python3 tools/review_release.py --strict \
  --mac-app .build/review-archives/FramepebbleMac.xcarchive/Products/Applications/FramepebbleMac.app \
  --ios-app .build/review-archives/FramepebbleiOS.xcarchive/Products/Applications/FramepebbleiOS.app
```

The tool checks artifact configuration and signature presence, not provisioning validity, website availability, legal correctness or approval. A zero exit status without `--strict` only means static artifact checks passed.

## Primary Apple references

[Review guidelines](https://developer.apple.com/app-store/review/guidelines/), [purpose strings](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-purpose-strings), [bookmark entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html), [privacy manifests](https://developer.apple.com/documentation/BundleResources/privacy-manifest-files), [app privacy definitions](https://developer.apple.com/app-store/app-privacy-details/), [universal purchase/platforms](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/), [SDK requirements](https://developer.apple.com/news/upcoming-requirements/?id=02032026a), [export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance).
