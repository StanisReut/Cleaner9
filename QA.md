# Cleaner verification — 2026-11-09

## Build and static checks

- Xcode Debug and Release simulator builds pass, deployment target iOS 17.
- Swift 6 / MainActor focused typechecks passed for Contacts and Calendar; media and background processing typechecks passed.
- 13 pure media-matching checks and 6 synthetic Contacts checks passed. These are model checks, not proof of device integrations.
- Asset catalog filenames resolve. App icon is 1024×1024 RGB without alpha. Privacy manifest passes plist validation.

## Simulator evidence

Pro: 402×874; SE: 375×667; Pro Max: 440×956. Primary routes use the same real views/services, exposed through a DEBUG-only `--qa-screen` launch argument. No production mock records are injected. Figma reference renders are cached under `~/.figma_cache/Cleaner-9/`.

Pro baseline: 15 primary screens captured and visually inspected. Real photo scan, swipe Keep/Undo, empty Trash, Contacts/Backups, calendar and settings navigation checked. Photo permission-denial recovery checked. Near-edge back control works.

SE baseline: 15 primary screens captured and visually inspected. Contact A–Z index and pinned deletion footers checked; system dark appearance preserves the design's light theme. Largest Dynamic Type defects were fixed and rechecked: controls scroll away to expose full contact cards; Home cards stack vertically; Settings banner remains readable. At the largest setting, phone numbers and avatar initials can still ellipsize (full phone accessibility labels remain available).

Pro Max: 15 baseline routes captured and visually inspected; normal startup Splash → Home verified. The old simulator input bridge failed on system permission dialogs, so native XCTest was used for functional verification.

Native XCTest on Pro Max passed two executed tests (not merely a successful build):

- Imported two separate files containing the same synthetic test video. Verified exact duplicate grouping, automatic selection of one copy, disabled deletion after deselecting, selection restoration, video preview, app/system confirmation, and success for exactly one deletion.
- Relaunched and rescanned: one original video remained. Created a local Contacts backup, restored it over existing contacts, verified **0 additions** and unchanged contact count.

Only one newly imported QA video was deleted. One QA video and an app-local contacts backup remain on this simulator. Existing media and contacts were not deleted.

Native evidence: [test source](qa/NativeUITests.swift), [deletion result](qa/video-deletion.png). Result bundles remain at `/tmp/cleaner-native-qa/result-confirmation.xcresult` and `/tmp/cleaner-native-qa/result-backup-selected.xcresult`. Temporary test project is separate from the production Xcode project. Its deletion test requires exactly two known QA videos; it fails closed otherwise. Earlier attempts failed on denied permission / a single imported file / an undismissed system dialog; these were test setup/input issues and were not counted as passes.

Detailed baseline evidence: [Pro report](qa/pro.md), [SE report](qa/se.md), [Max report](qa/max.md), [SE accessibility screenshots](qa/se-accessibility.jpg). Native results above supersede the Max report's earlier unverified media/backup status.

These passes cover baseline layout and selected flows, **not every Figma state or a pixel-perfect certification**. Real counts differ from the design's illustrative values.

## Material unverified paths

- Vision foreground segmentation returns `Could not create inference context` on the tested Pro simulator. Error/retry is verified; successful segmentation, PNG save and sharing require a physical device check.
- Email breach provider, subscription products, support email and legal URLs have not been supplied. Their screens explicitly report unavailable functionality.
- Real StoreKit purchase, renewal, cancellation and restore require configured products/account testing.
- Contact merge/delete, restore into a library missing contacts, and writable calendar deletion require further fixture/device coverage. Restore deduplication over an unchanged library passed.
- Approved splash motion archive/onboarding design was not provided. Current startup uses the Figma artwork with a timed fade to Home.

See [DEVICE_DATA_LIMITS.md](DEVICE_DATA_LIMITS.md) for operational limits, including cloud-only media, contact field preservation and calendar ranges.
