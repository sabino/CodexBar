---
summary: "Architecture overview: modules, entry points, and data flow."
read_when:
  - Reviewing architecture before feature work
  - Refactoring app structure, app lifecycle, or module boundaries
---

# Architecture overview

## Modules
- `Sources/CodexBarCore`: fetch + parse (Codex RPC, PTY runner, Claude probes, OpenAI web scraping, status polling).
- `Sources/CodexBar`: state + UI (UsageStore, SettingsStore, StatusItemController, menus, icon rendering).
- `Sources/CodexBarCross`: one SwiftCrossUI compact window and settings UI for Linux, macOS, and Windows.
- `Sources/CodexBarCrossSupport`: renderer-neutral navigation, history-loading, and resize-coalescing seams.
- `Sources/CPlatformTray`: native tray adapter (StatusNotifierItem, NSStatusItem, and Shell_NotifyIcon).
- `Sources/CodexBarWidget`: WidgetKit extension wired to the shared snapshot.
- `Sources/CodexBarCLI`: bundled CLI for `codexbar` usage/status output.
- `Sources/CodexBarClaudeWatchdog`: helper process for stable Claude CLI PTY sessions.
- `Sources/CodexBarClaudeWebProbe`: CLI helper to diagnose Claude web fetches.

## Entry points
- `CodexBarApp`: SwiftUI keepalive + Settings scene.
- `AppDelegate`: wires status controller, Sparkle updater, notifications.
- `CodexBarCrossApp`: selects GTK, AppKit, or WinUI at compile time and presents the compact and settings windows from
  the same view tree.

## Data flow
- Background refresh → `UsageFetcher`/provider probes → `UsageStore` → menu/icon/widgets.
- Cross-platform refresh → `ProviderRuntimeSession`/`CostUsageFetcher` → `CodexBarCrossModel` → compact window,
  settings, and native tray.
- Settings toggles feed `SettingsStore` → `UsageStore` refresh cadence + feature flags.
- Runtime-only provider settings flow through typed, descriptor-registered sections in `ProviderSettingsSnapshot`.

## Concurrency & platform
- Swift 6 strict concurrency enabled; prefer Sendable state and explicit MainActor hops.
- The original app targets macOS 14+. `CodexBarCross` compiles on Linux, macOS, and Windows while keeping
  platform-specific imports behind narrow compile-time adapters.

See also: `docs/providers.md`, `docs/refresh-loop.md`, `docs/ui.md`, `docs/CROSS_PLATFORM.md`.
