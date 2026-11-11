# SE simulator QA

Device 199C3299-1F62-4EFF-B5B2-9429867F57EA; 375×667 points. Latest installed build. Fifteen real DEBUG route screenshots and accessibility trees captured; sheet0–2.jpg visually inspected. Calendar119-1912 and Contacts94-1327 cached Figma PNGs directly compared. No source edits, user-data deletion, backup creation or purchases performed.

## Baseline route families

| Family | Observed result | Limit |
| --- | --- | --- |
| Home | Layout readable; real storage card, premium and media rows; lower content scrolls. | Initial Ready to scan values shown, not an assertion that scans completed. |
| Smart Scan | Scanning artwork/progress rendered; capture at85%. | Final completion not captured in this pass. |
| Photos | Figma-style intro, artwork, readable copy and pinned Let’s Go fit. | Loaded category navigation not exercised in this pass. |
| Swipe | Real portrait, Keep/Delete/Trash controls fit. | No deletion or swipe action tested. |
| Videos | Five empty real categories rendered. | No videos available; playback/compression not verified. |
| Contacts | Six real contacts, hub cards fit. Child list shows initials and64pt rows. | Duplicate/merge and backup/restore actions not exercised. |
| Calendar |100 real past events, year/count sections, date/dot/calendar rows. Delete footer visible at y603.5. | Data read only; no writable event deletion performed. |
| Background | Before/after intro, readable copy and pinned Choose photo fit. | Known simulator Vision inference limitation not repeated; successful editor/export requires device. |
| Security Center | Hero and three status cards readable. | No provider call tested. |
| Settings | Six rows, premium banner and version fit at default text. | External links and purchase actions not exercised. |
| Subscription | Honest unavailable-product state; controls fit. | StoreKit product IDs unconfigured. |
| Email | Empty input and disabled Check fit. | Provider unconfigured. |
| Password | Empty secure field, privacy explanation and disabled check fit. | Network request not tested. |
| Device Security | Three review cards readable; lower action requires scrolling. | These are self-review controls, not system inspection. |
| Splash | Artwork and wordmark fit. | DEBUG route adds back chrome; normal timed startup not tested. |

## Contact child interaction

contacts-list.png and contacts-jump-k.png show the real alphabetical list. Fresh accessibility data reports all jump buttons44×44 points. Tapping Jump to K moves Kate Bell from y713.5 to y499.5, into view. Delete0 Contacts remains pinned at y603.5 before and after the jump. No selection or delete confirmation was accepted. Default name/number rows remain within bounds.

## Accessibility and appearance

- Largest accessibility text (`accessibility-extra-extra-extra-large`) **fails visual fit** on SE: contact header, count and selection control truncate; names have very limited readable room. The pinned delete action remains on-screen but occupies137pt.
- Settings at largest text has severe premium-banner word splitting and the bottom Version area overlays scrolling lower rows. See contacts-accessibility.png, settings-accessibility.png and extras.jpg. Do not claim accessibility-size support passed.
- Home under system dark appearance deliberately remains light, matching the app’s Figma theme; screenshot home-system-dark.png.
- Restored system appearance to light and text size to large after checks.

## Fidelity and coverage

Calendar now follows the design’s year grouping and individual cards; real read-only rows are more muted and the explicit date-range disclosure adds height. Contacts hub icons/disclosures differ from Figma silhouettes. Baseline layouts are usable, not pixel-perfect. This is a15-route baseline plus contact-index/theme/text-size sample, **not a pass for all31design states or all real actions**.

Initial automation captures were blocked by a persistent Photos full-access system prompt despite simctl grant; explicit Allow Full Access resolved it, and all15route captures were replaced. An idb tap rejected floating-point coordinates; rounding to integer points fixed the QA script. Neither issue was an application crash.


## Latest-build accessibility recheck (supersedes earlier defects where stated)

Installed the newly rebuilt app. Evidence: recheck.jpg and recheck-contacts-default/selected/accessibility, recheck-settings-accessibility PNG and AX files.

- Default Contacts still fits. Select all selects all six contacts; pinned Delete6 Contacts remains y603.5 with47.5pt height. No delete action accepted. AX reports Select all label bounds19.5pt high; code-expanded hit area was not separately measured.
- Maximum accessibility size: Contacts header now wraps fully, count and Deselect all are readable vertically, and Delete6 is fully readable. Earlier text truncation is fixed.
- **Remaining accessibility usability failure:** the non-scrolling header/search/selection controls plus137pt pinned delete footer leave only roughly74pt for the contact list. The screenshot shows letter A and effectively no readable full contact row; a large multiline name/number card cannot fit in that viewport at once. The controls need to share scrolling space or otherwise reserve sufficient list space.
- Settings premium banner now uses a readable vertical layout; Upgrade no longer splits. Version is capped and opaque, no longer overlays content. Manage subscription still wraps its final n onto a third line at maximum size, awkward but not hidden. Lower settings rows require scrolling.
- Restored large text and light appearance. Device released; no code changes.


## Final targeted accessibility recheck

Newest build installed; tested only the changed Contacts list and Home at maximum accessibility size. Evidence: final-accessibility.jpg, final-contacts-jump-a.png and matching AX.

- Contacts viewport starvation is fixed: search and selection controls scroll away. Jump to A positions the entire first contact card at y263.5–438, above the pinned footer at y568.5. The shortened Delete0 footer is82.5pt tall and exposes the full accessibility label. Name wraps; phone number remains single-line ellipsized at this extreme size, with full number in the accessibility label. Initials in the fixed40pt avatar also ellipsize at maximum text. These residual text details do not hide the full card or selection control.
- Home now presents storage and metric cards vertically. Three scroll captures show complete readable Photos, Videos, Contacts and Calendar labels, real counts, and readable Media cleanup/Ready to scan. Premium text no longer breaks words vertically, and the storage percentage stays within its ring. Some content naturally leaves the viewport while scrolling; no new severe fixed-layout obstruction observed.
- Default large text and light appearance restored. No destructive action, source edit or expanded screen audit. Device released.
