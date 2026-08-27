# Changelog

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
