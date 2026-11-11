# Cleaner implementation

Scope confirmed: all sections from Cleaner 9, starting at Main, with real device data and actions.

Use SwiftUI and native Apple frameworks: PhotoKit for media and deletions, Vision for image similarity and foreground extraction, Contacts for contacts/backups/merge, EventKit for calendar, StoreKit for verified subscription status. Keep design constants and reusable UI separate from services. Use the provided Figma frames and annotations as the source of truth; sample counts are not application data.

Order: design extraction/assets → services and shared UI → Main/Smart Scan/media → contacts/calendar → background removal/security/settings → build, failure-path checks and SE/Pro/Max visual comparison.

Deletion requires explicit review and confirmation. Best media is excluded from automatic selection. Swipe decisions only stage deletion. Merge preserves unique contact fields and creates a backup before mutation. Failed operations must not show success. No fabricated breach, subscription, or device security results.

External inputs pending: subscription products and access rules; email breach provider; support email and legal URLs; approved splash motion archive. Missing integration must be reported as unavailable, never as a successful check.

Verification status: local feature sections implemented; Debug and Release simulator builds pass. Primary SE/Pro/Max layouts checked. Native XCTest verified duplicate video selection/deletion, retaining one copy, and Contacts backup/restore deduplication. See QA.md for exact coverage and unresolved device/external paths. This is not a claim that every Figma state or external integration has passed.
