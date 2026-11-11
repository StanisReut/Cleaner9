# Extended-state fixes — 2026-11-11

## Changes

- Accessibility result modals use the available width and a safe-area scroll container. The full title/message and primary/secondary actions remain in the same scrollable content. Normal-size modal artwork/layout is preserved.
- Photo and swipe introductions use natural text height at accessibility sizes instead of a fixed-height GeometryReader stage.
- Smart Scan summary text grows vertically; the progress numeral inside fixed artwork has a bounded visual size.
- Media review sorting and selection become vertical at accessibility sizes and scroll together with the list, preserving a usable media viewport.
- Fixed thumbnail badges, video metadata and swipe-state decorations have bounded text sizes; standalone names and actions continue scaling.
- Photo Swipe places Trash below the heading at accessibility sizes. Home branding scales to fit a single line; Splash branding retains its designed display size.
- Contact restore illustration retains readable design text and its existing combined accessibility label; status content scrolls while Cancel stays available. Contact initials scale within their avatars.
- Calendar year headings and event metadata stack at accessibility sizes. Empty calendar text can scroll instead of truncating.
- Settings, photo-intro and tool-action footers use opaque backgrounds at accessibility sizes so scrolling content is not painted through them. Background editor controls grow naturally and have bottom separation.
- Primary action labels wrap to their full natural height.

## Verification

Final production build succeeded; see [build evidence](fix-build-evidence.json). The [extended-state matrix](REPORT.md) is regenerated from per-device observed results, with initial defects retained in review history. Screenshot capture alone is not a passing verdict. XCTest performs scroll reachability and modal-action checks on installed builds.

Standard-text comparisons use the cached2026-11-10 Figma source. Maximum-text layouts have no dedicated Figma frames and are assessed for readable adaptation, not pixel identity. External-setup limitations remain documented in [source gaps](source-gaps.md).
