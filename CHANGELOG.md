# Changelog

## Unreleased

- Fix MiniMax Desktop quota refresh by decoding Brotli cache responses and percentage strings, showing unlimited weekly quotas explicitly, and retaining marked stale samples during incomplete writes.

- Read current Codex quotas through the installed CLI’s official read-only app-server interface, retain local-log fallback with a bounded timeout, refresh when opening the panel, and explain expired windows instead of reporting missing data.

## 1.2.2 — 2026-11-12

- Automatically prepare a patch version and build number on main updates, synchronize release records, push the version commit and tag atomically, and call the existing Release workflow without extra credentials.
- Make GPU-dependent preview export opt-in so Intel hosted runners can complete all quota logic and menu-ring image tests without a Metal assertion crash.
- Add automated universal DMG releases for version tags and manual rebuilds, preserving version/test gates and uploading DMG plus SHA-256 to Actions and GitHub Releases.
- Import the complete `standard-dev-flow` skill from `ai_novel_agent`, including Issue/design templates and agent metadata, while retaining the current project's development workflow.
- Adopt native macOS 26 Liquid Glass with persistent background transparency, accessible material fallback, and model-logo rings for 5-hour quota usage in the menu bar and detail cards.
- Adopt MacEverything's About/changelog update workflow, numbered change records, shared Make targets, and dual-architecture PR checks; pin the test language without changing user preferences.
- Stop displaying expired Claude quota samples as current values after refresh, and explain how to collect a new sample.
- Select Claude quota sources per window so newer snapshots with missing fields do not hide available limits.
- Keep local Claude token totals visible when quota snapshots are unavailable.

Detailed change records and validation: [change index](docs/changelog/README.md).

## 1.2.1 — 2026-09-26

- Re-register the launch-at-login item when AI Usage runs from a new location, so macOS no longer keeps starting an outdated copy (such as an Xcode build) at login.
- Keep Debug builds from taking over the installed app's launch-at-login item.

## 1.2.0 — 2026-08-27

- Add MiniMax API Key authorization for Mainland China and Global regions, with credentials stored in macOS Keychain and verified only through official model-list endpoints.
- Make MiniMax Desktop quota-cache parsing tolerate JSON whitespace and reordered top-level fields.
- Fix missing Claude Code token history in large transcripts by scanning backward to the seven-day boundary and parsing new records incrementally.
- Remove expired Claude history from in-memory caches while keeping the last valid quota sample displayed normally until Claude records a newer call.
- Prevent outdated MiniMax authorization responses from overwriting the result after the selected region or API Key changes.
- Add release-version validation for tags, project metadata, the About view, built apps, and GitHub tag builds.

## 1.1.0 — 2026-07-27

- Add Kimi Code local token usage, menu bar display, provider selection, and seven-day history.
- Parse current `usage.record` events incrementally and support legacy `StatusUpdate` events with message-level deduplication.
- Show Kimi Desktop subscription usage and reset time from its local application log.
- Add the Kimi Code icon and document its local-only, credential-free data collection.
- Allow usage cards to be reordered by dragging and remember the preferred provider priority after relaunch.
- Add MiniMax Desktop subscription usage as the sole MiniMax data source, showing official 5-hour and weekly usage percentages and reset times from its local HTTP cache without reading credentials, API logs, or conversation content.
- Limit menu bar usage display to the first three selected providers in the saved detail-card priority order; additional providers remain available in the detail view.
- Enlarge the Settings window and fit all General and Integration content without requiring scrolling.
- Infer Claude Code seven-day reset time from Claude Desktop usage transitions when the official status-line reset timestamp is unavailable.
- Show calendar dates instead of weekday names for reset times more than 24 hours away.
- Treat Kimi Desktop's subscription expiry as a date-only refresh value instead of displaying a misleading timezone-derived clock time.
- Add official Kimi Code 5-hour and weekly quota windows through the Kimi usage API, with API keys stored in macOS Keychain.

## 1.0.1 — 2026-07-23

- Fix Claude Code usage being missing or visually indistinguishable in history.
- Give Codex and Claude Code independent charts and vertical scales.
- Improve the history window size, equal-height provider layout, and seven-day bar proportions.
- Add provider icons, daily values, seven-day totals, and provider-specific empty states.
- Bring an existing or minimized history window to the foreground when History is clicked again.
- Add regression coverage for Claude Code daily history aggregation.

## 1.0.0 — 2026-07-22

- Add Codex and Claude Code usage monitoring.
- Add Claude Desktop plan-usage support.
- Add multi-provider menu bar display.
- Add Simplified Chinese and English interfaces.
- Add light, dark, and system appearance modes.
- Add configurable refresh interval and provider selection.
- Add local Claude Code status line integration.
- Add usage history, launch-at-login support, and macOS AppIcon assets.
