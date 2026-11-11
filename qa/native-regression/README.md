# Native regression — 2026-11-10

Device: `78E2D20F-FC73-4A71-AB9B-A9CCC768E15E` (PhoneCleaner-Native-QA), iOS 26.5, 402×874 pt. System language Russian; application copy English. XCTest drove the real application with `--qa-screen` routes for media and contacts. Handoff/modal cases used the existing fidelity routes.

## Confirmed results

| Test | Result | Evidence |
|---|---|---|
| Native photo picker, share sheet, both add-only permission routes | Pass. Actual system interfaces displayed. Permission declined; handoff test never saved an image. | `handoffs-modal.log`, `attachments/manifest.json`, `native-handoff-sheet.jpg` |
| Back to Settings secondary modal action | Pass. AX hit frame at least 44 pt high; center and 92%-height lower-edge taps each dismiss the modal. | `handoffs-modal.log`, `modal-attachments/manifest.json` |
| Contacts backup/restore idempotence | Pass. Six preflight-verified Apple sample contacts; created backup, restored it, obtained “0 contacts restored”, original hub count unchanged. | `contacts.log`, `contacts-attachments/manifest.json` |
| Real video scrub, finish, replay, duplicate deletion | Pass after precise-seek fix. 80% drag on owned 2-second clip holds `00:01`; playback reaches end and replay restarts. Deselect all disables deletion. Only one deliberately selected owned duplicate was deleted; exactly one result modal appeared; owned other copy remains. | `video-after-fix.log`, `video-attachments/manifest.json`, `media-preservation.json` |

These are functional results, not pixel-equivalence verdicts for OS-owned interfaces. Tests passed in separate focused runs; the earlier combined run contains harness failures described below and must not be called an all-green run.

## Reproduced product defect and fix verification

Before the precise-seek change, the drag visibly advanced to 80%/`00:01`, then the player and AX value returned to `00:00`. See `video-before-fix.log`, `seek-before-fix-ax.txt`, `seek-before-fix-sequence.jpg`, and `seek-before-fix.png`. The exact same UI test passed after both production seeks received zero before/after tolerance.

A standalone direct-file AVPlayer probe returned 1.6 seconds with both default and zero tolerance on macOS and iOS simulator (`seek-probe.log`). Therefore the failure is established for the real PhotoKit/UI path; generic keyframe snapping is not proven to be its root cause.

## Harness corrections

- Removed nonexistent `XCUIProtectedResource.photosAddOnly` (verified against installed SDK header); `.photos` reset produced both requested native permission prompts.
- Native selectors accept observed English/Russian picker and permission labels.
- The preview sheet and underlying review screen both expose Select item; selection targets the foreground first match and asserts hittability.
- Contacts permission was granted during preflight. The earlier contacts run waited on Loading contacts while permission was unresolved; it was not an app-crash result.

## Data safety and cleanup

Before testing, existing device contacts were checked to be exactly the six Apple sample contacts. Existing media were preserved. Two synthetic videos were imported from the owned QA fixture. The deletion test clears all selection, identifies exactly two previews whose filename contains `cleaner-test-video`, opens the second, selects only that item, and requires the one-video delete count.

Read-only Photos database comparison confirmed exactly one change: `cleaner-test-video.mp4` moved to Recently Deleted. Zero unrelated asset/trash-state changes; `cleaner-test-video-copy.mp4` remains. The simulator was shut down after verification. No QA server or helper remains running.

## Reuse

`FidelityRegressionTests.swift`, `project.yml`, and the synthetic `cleaner-test-video.mp4` are retained here. Generate with `xcodegen generate --spec project.yml`; build/test with `xcodebuild`, an explicit simulator UDID, isolated DerivedData, and `-parallel-testing-enabled NO`. Run contacts/deletion cases only after the safe-data preflight described above. For the video case, import exactly two named copies of the fixture and ensure no prior owned duplicate population remains; the test intentionally fails closed when it cannot isolate two owned previews.

Full local result bundles:

- `/tmp/cleaner-native-regression-all.xcresult` — successful handoffs and modal action; contains earlier harness failures in media/contacts.
- `/tmp/cleaner-native-regression-live-v2.xcresult` — successful contacts; contains the pre-correction ambiguous video selector.
- `/tmp/cleaner-native-regression-video-v3.xcresult` — reproduced scrub regression before precise seeks.
- `/tmp/cleaner-native-regression-video-v4.xcresult` — passing real video regression after fix.
- `/tmp/cleaner-native-regression-seek-probe.xcresult` — direct-file diagnostic probe.
