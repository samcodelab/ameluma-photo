# Local signing status

The Xcode project uses development team PLQG3PMFP8. The existing Apple Development identity signs the macOS application locally; signature validation is performed using the system trust store. No identifiers, provisioning profiles, entitlements or App Store records were registered remotely.

An iOS device build currently lacks a provisioning profile for com.broadframestudio.framepebble.ios. Simulator builds remain available without device provisioning. The user chose local signing only; do not run provisioning-update registration commands without new authorisation. Sensitive Content Analysis remains unavailable until its capability and system policy permit analysis.

Signed sandbox builds use the platform sandbox container; an older unsigned development workspace may be in a different application-support location. Preserve existing projects and use project opening/relinking rather than deleting or overwriting user storage. Public privacy/support URLs and distribution provisioning remain outstanding before submission. Local development signing is not App Store release approval.
