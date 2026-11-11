# Pro Max simulator QA

Device: 5E42ECEA-6985-4514-8348-CFC60913613B, 440×956 points. Latest supplied installed build. No source edits or user-data mutations.

## Layout baseline

All 15 DEBUG routes have PNG screenshots and JSON accessibility captures in this directory. Contact sheets sheet0.jpg–sheet2.jpg were visually inspected.

- Home: readable storage and feature cards, lower content scrolls. The initial 0 media counts are not completed scan results (main already changed initial copy in source afterward).
- Scan / Videos: readable denied-photo-access recovery state with Settings and Try again. Successful scan/results/video playback were not verified.
- Photos: Figma collage, title, copy and pinned Let's Go fit.
- Swipe: empty-state explanation and Trash fit; no swipe transaction tested.
- Contacts: six simulator sample contacts, duplicate/incomplete/backup counts and cards fit. Backup and restore not exercised.
- Calendar: 100 real past events, year heading, date rows and pinned disabled Delete 0 fit. Existing events were not modified.
- Background: source before/after illustration, explanatory text and pinned Choose photo fit; processing/export not tested.
- Security / Settings / Subscription / Email / Password / Device: titles, content and controls fit. Empty fields disable their checks. Subscription clearly states purchases unavailable. No provider calls, purchases or restore transaction tested.
- Splash DEBUG route: artwork fits, but debug navigation back chrome is present and is not evidence for normal startup. Separate normal-splash.png and normal-home.png capture normal launch.

This is a default-text light-theme baseline, not a complete state, accessibility-size or pixel-perfect audit.

Normal startup was separately verified visually: normal-splash.png shows the full splash without navigation chrome; normal-home.png captured four seconds later shows Home. The first earlier immediate screenshot caught the iOS launch transition, so normal-startup-immediate.png should not be used as splash evidence.

## Interaction blocker and recovery evidence

Initial Photos full-access prompt persisted across routed launches. Fresh AX returned Allow Full Access at center 220,732 points. idb taps (including press duration and explicit device ID) returned success but left the prompt unchanged; hardware Home also had no observed effect. Granting Photos permission with simctl did not settle the pending prompt. SpringBoard restart cleared the orphaned overlay and allowed the baseline captures above, showing proper denied-access recovery.

One device reboot and companion restart were attempted. Vanilla companion exposed a missing SimulatorKit framework error; restarting with the supplied sanitized compatibility DEVELOPER_DIR resolved that error but still produced no observable response to the fresh permission-button tap. No additional reboot loop was attempted. This is an automation/input limitation, not evidence of an application crash.

No synthetic fixture was imported; no photo/video/contact/calendar record was deleted or modified. Duplicate-video default selection, deselect/disabled state, preview playback, deletion confirmation/count, Best preservation, and Contacts backup/restore remain unverified. Do not report these as passed.

The temporary helper is stopped after verification. The simulator remains booted for the main agent; no test server or recording was started.
