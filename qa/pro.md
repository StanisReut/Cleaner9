# Pro simulator QA

Device: 1599FF1F-F246-49A2-9AE7-3CB25F6375B8, 402×874 points. Final app installed from /tmp/PhotoCleanerApp-build/Build/Products/Debug-iphonesimulator/PhotoCleanerApp.app. Fifteen final real-screen routes captured as final-*.png and final-*-ax.json. sheet0–2.jpg visually inspected. Reference renders 4-214, 94-1327,147-2387 and cached background/splash design contexts inspected. No project edits or data deletion during QA.

## Results

| Screen | Result and evidence |
| --- | --- |
| Home | Layout passes visible top; real storage value. Initial media Ready to scan/0 is initial state, then scan updates to13 photos/24MB. Final Contacts0 duplicates/Calendar100 counts present. Earlier home-bottom screenshot confirms lower feature rows accessible. |
| Smart Scan | Navigation and successful scan complete; zero matching categories truthful. Final layout clear; long category list scrolls. Loaded duplicate-group state not verified. |
| Photos |13 real Other Photos loaded. Final categories use preview stacks. Duplicate empty state shows Nothing here. |
| Photo Swipe | Real portrait renders. Keep advances and exposes Undo. Empty Trash opens. No destructive delete executed; final irreversible deletion untested. |
| Videos | Five real categories render empty. No videos in library; player, compression and loaded video deletion untested. No fixture imported. |
| Contacts |6 contacts loaded, duplicate/incomplete0. Final cards readable; actual final count reflects library. Loaded duplicate merge untested. |
| Backups | Empty screen and Create backup control render. Did not create or restore private-contact backup. |
| Calendar |100 real past events loaded, read-only status presented. Final grouping/year counts render. Prior bottom-of-scroll Delete usability defect fixed: final footer pinned at bottom. No writable event deletion tested. |
| Background Remover | Picker opens and portrait selection reaches Vision. Simulator returns “Could not create inference context”; recoverable Try again/Choose another shown, no crash. Editor/save/share cannot be passed on this runtime. Final intro now uses actual before/after artwork, centered copy and pinned Choose photo; prior eraser-art defect fixed. |
| Security Center | Final hero and three cards visually align reference structure. Honest Not checked state. |
| Email | Real input and disabled empty Check visible. External breach lookup unconfigured/not tested. |
| Password | Secure input and disabled empty check visible; privacy text readable. No password entered and network check untested. |
| Device Security | Three self-review toggles and How to check. Tapping guide opens real system-path alert, dismiss works. No system-security claim fabricated. |
| Settings | Final six64pt rows + premium and bottom version fit. Navigation to subscription works. External links/purchases untested. |
| Subscription | Honest No active subscription/Premium purchases not available yet state. No actual StoreKit purchase configured or verified. |
| Splash | Final QA route shows brand/gradient/wordmark. QA route adds NavigationStack Back; not evidence of production startup chrome. Timed normal-launch transition not captured in this pass. |

## Remaining visual differences / limits

- Shared layout is now close in structure, colors and card radii; no pixel-perfect claim. Contacts uses different outlined icon silhouettes and card shadows than reference. Real values differ from mock values by design.
- Home and long Smart Scan content need scrolling on this device; not all features fit in a single viewport as in the unusually tall Home reference export.
- Background Vision processing needs real-device verification; successful segmentation, output alpha, sharing completion and add-only save were code-reviewed/typechecked but not runtime-proven here.
- Final capture only Pro/light/default text. SE/Max, dynamic type, dark appearance handled separately by parent. Final build screenshots supersede earlier pre-fix screenshots.
-44pt back hit target verified repeatedly by tapping x10,y90 near its left edge.

No QA server created by this agent. Existing idb companion owned by parent remains. Simulator released to parent after report.
