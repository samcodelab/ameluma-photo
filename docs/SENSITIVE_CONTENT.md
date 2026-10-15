# Temporary privacy review

Privacy Review supports manual flags, a matching gallery filter, concealed flagged previews, explicit reveal, and routes into masking/cropping. Flags and Apple findings are temporary and deliberately absent from persistent projects. Changing a source invalidates its automatic finding. Detection has no spatial mask geometry and does not automatically censor or delete sources.

The platform adapter uses Apple Sensitive Content Analysis with oriented, downsampled images. Its actual analysis policy gates availability. Disabled policy is reported, and manual review remains available. Final-output sharing checks invalidate approval and require completion or explicit manual review before handoff. Test detectors are injected only in automated tests; production never invents findings.

The current local-signing configuration does not include the Sensitive Content Analysis entitlement. Automatic checks therefore cannot be claimed as operational in this build. Activation requires Apple's permitted capability/provisioning and enabling relevant system settings. No developer registration was authorised. Detection is not a guarantee that an image is safe, and may miss content. Use opaque covers or cropping when stronger concealment is needed, and inspect final output.

Reference: https://developer.apple.com/documentation/sensitivecontentanalysis/scsensitivityanalysispolicy/disabled
