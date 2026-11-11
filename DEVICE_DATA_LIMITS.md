# Device data and configuration limits

These are current implementation limits, not promises of complete recovery or comprehensive security scanning.

## Contacts and backups

- Only contacts authorized by iOS are visible. Limited access also limits duplicate detection and restore deduplication.
- Duplicate groups use shared phone numbers after removing non-digit characters. Country-code variants are not inferred.
- **Combine details keeps every original contact.** It copies unique labeled fields into the first contact, after saving a vCard backup. Conflicting scalar fields block the operation. It does not remove duplicate records or claim to preserve inaccessible fields by deleting them.
- vCard backups can omit protected notes and account-specific metadata. Deleting a contact can therefore lose information that the backup cannot recover; the confirmation discloses this.
- Backups are local app files. Uninstalling the app removes them; export a vCard to keep an independent copy.
- Restore adds contacts to the default Contacts container without replacing existing records or recreating original account membership. Fingerprints and receipts skip known existing entries. A partial failure reports how many entries were saved.
- Contact queries run off the main actor. Contact save requests and vCard serialization still run on the main actor and can briefly stall large operations.

## Calendar

- Requires full calendar access. Past covers the previous three years; Future covers the next three years. The UI shows the date range; queries use one-year windows.
- Past includes events that have ended; Future includes events that have not started. Currently ongoing events are outside those lists.
- Read-only calendars cannot be selected for deletion. Recurring-event deletion affects only the selected occurrence, not the series.
- Each deletion is committed independently. Partial failures retain successful deletions and report their actual count. This feature does not create calendar backups or provide undo.

## Photos and videos

- Results include only assets shared with the app. Files whose resources are not fully available locally are excluded from byte totals and exact-duplicate checks; download originals in Photos and rescan. Playback may request an iCloud download.
- Exact matching compares all available asset resources. Similar-photo detection is heuristic, restricted to the same day and similar aspect ratio; recommendations require user review.
- Reported media bytes describe measured file resources, not a guarantee of immediately reclaimed device storage.
- Background removal uses on-device Vision. Processing caps the longest image edge at 4,096 pixels; exported results can therefore be smaller than the original. Subject detection can fail and exposes a retry path.

## Security and external configuration

- **Email breach checking has no configured provider.** The screen reports that checking is unavailable; it does not send the email address or fabricate a result.
- Password leak checks use Have I Been Pwned's range API, sending only the first five SHA-1 hash characters. Strength is an estimate, and absence from that dataset does not establish safety. Network failures are reported as unavailable checks.
- Device Security is a user-maintained checklist. The app cannot inspect passcode, Apple Account two-factor authentication, or update status.
- **Subscription product IDs are empty** in `PhotoCleanerApp/SettingsScreen.swift` (`ProductConfiguration`). StoreKit purchase and entitlement handling exists, but real products and restore validation require published product configuration and a suitable App Store test environment.
- Support email, Terms URL and Privacy URL are also unset in `ProductConfiguration`; those destinations must be supplied before release.

Real account permissions, synced providers, cloud-only originals and StoreKit purchases require device/account testing. Synthetic model checks and simulator UI checks do not establish those integrations end to end.
