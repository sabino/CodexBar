---
summary: "Compatibility and release priorities for the native Swift cross-platform fork."
read_when:
  - Planning fork work
  - Reviewing compatibility priorities
  - Deciding whether a feature belongs in shared core or a platform adapter
---

# Fork roadmap

## Current foundation

- One SwiftCrossUI view tree builds on Linux, macOS, and Windows.
- The compact provider window, full settings window, searchable provider sidebar, Usage & Spend dashboard, native tray,
  provider artwork, resizable panes, and native controls are implemented.
- Historical usage uses the original incremental scanner and SQLite store. Automatic work is bounded and cached;
  explicit Refresh completes a full historical pass.
- The original SwiftUI/AppKit macOS app and CLI remain in-tree and continue to receive upstream changes.

## Near-term priorities

1. Keep `upstream/main` mergeable and avoid copying provider logic into the UI target.
2. Expand renderer-neutral tests for navigation, controls, tray commands, resize delivery, history coverage, and cache
   loading before adding platform-specific workarounds.
3. Validate every released build on real Linux and macOS hosts in addition to CI smoke tests; restore Windows release
   artifacts only after the WinUI build is fast and stable enough to gate tags.
4. Close portable authentication gaps only through narrow adapters; never show account data from another provider.
5. Keep idle memory, refresh CPU, and archive I/O measurable and bounded on large local Codex histories.

## Compatibility policy

Provider changes should land in `CodexBarCore` whenever the behavior is genuinely portable. UI code consumes the
shared typed models and must not fork parsers, pricing, or history calculations. Platform-only capabilities stay
behind compile-time adapters and fail soft when an operating system has no equivalent.

The goal is a contribution-ready diff, but publishing an upstream pull request is always a separate explicit action.
Fork releases do not alter the upstream appcast, signing identity, Homebrew tap, or release tags.
