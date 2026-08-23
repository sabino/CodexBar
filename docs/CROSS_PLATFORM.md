---
summary: "Build, install, and maintain the native SwiftCrossUI desktop app for Linux, macOS, and Windows."
read_when:
  - Building or installing CodexBarCross
  - Debugging its tray, renderer, settings, or usage history
  - Publishing cross-platform desktop release assets
---

# Cross-platform desktop app

`CodexBarCross` is the native Swift desktop port in this fork. It keeps provider parsing, authentication sources,
quota models, pricing, and historical usage in the same `CodexBarCore` used by the original CodexBar app and CLI.
Linux, macOS, and Windows render one SwiftCrossUI view tree; only the window, tray, and native-control adapters vary by
platform.

The original SwiftUI/AppKit app under `Sources/CodexBar` remains the canonical signed and notarized macOS product.
The cross-platform app is a second executable, not a rewrite of provider logic and not an Electron or Rust shell.

## What is shared

- The provider registry, fetchers, parsers, usage snapshots, account metadata, status probes, and dashboard links come
  from `CodexBarCore`.
- The compact provider window, full settings window, provider search, Usage & Spend dashboard, custom provider icons,
  and tray menu use one Swift implementation under `Sources/CodexBarCross`.
- `CPlatformTray` supplies `NSStatusItem` on macOS, `Shell_NotifyIcon` on Windows, and StatusNotifierItem over D-Bus on
  Linux.
- `CodexBarCrossSupport` contains renderer-neutral navigation, history-loading, resize-coalescing, and presentation
  helpers that can be tested without creating native windows.

Some integrations have no portable equivalent. WidgetKit, Sparkle, macOS Keychain and browser-cookie bridges,
Accessibility-driven window focus, and other AppKit-only surfaces remain in the original macOS app. A provider works
in `CodexBarCross` when its underlying CLI, API, config file, OAuth source, or other `CodexBarCore` source exists on the
host platform.

## Release downloads

Cross-platform releases use tags such as `v0.54.1-cross.1` and contain:

| Platform | Asset | Notes |
| --- | --- | --- |
| Linux x86_64 | `CodexBarCross-v<version>-linux-x86_64.tar.gz` | Stripped executable with its Swift runtime libraries; GTK/GLib/SQLite remain system libraries. |
| macOS arm64 | `CodexBarCross-v<version>-macos-arm64.zip` | Ad-hoc signed, not Apple-notarized. |
| macOS x86_64 | `CodexBarCross-v<version>-macos-x86_64.zip` | Ad-hoc signed, not Apple-notarized. |
| Windows x86_64 | `CodexBarCross-v<version>-windows-x86_64.zip` | Includes Swift and SQLite DLLs; Windows App Runtime is installed separately. |

Each archive has a matching `.sha256` file. Download releases from
<https://github.com/sabino/CodexBar/releases>.

### Linux

Install the GTK 4, GLib/GIO, and SQLite runtime libraries. On Ubuntu 24.04:

```bash
sudo apt install libgtk-4-1 libglib2.0-0 libsqlite3-0
tar -xzf CodexBarCross-v*-linux-x86_64.tar.gz
./CodexBarCross/CodexBarCross
```

The tray implementation uses StatusNotifierItem. KDE, modern GNOME extensions, and compatible panels can host it
directly. An XEmbed-only panel, including some i3 bars, needs a bridge such as `snixembed`. Escape hides the compact
window; the custom close button does the same without relying on window-manager decorations.

### macOS

Extract with `ditto`, then open the app:

```bash
ditto -x -k CodexBarCross-v*-macos-arm64.zip .
open CodexBarCross.app
```

Fork builds are ad-hoc signed for reproducible CI packaging and are not notarized. Gatekeeper may require an explicit
Open action. Use the original CodexBar release when Developer ID signing, notarization, Sparkle updates, WidgetKit, or
the complete macOS integration set is required.

### Windows

Install the x64 Windows App Runtime `1.5.240205001-preview1`, extract the archive, and run
`CodexBarCross/CodexBarCross.exe`. The release workflow smoke-tests this exact runtime because SwiftCrossUI 0.9.0's
WinUI backend targets it.

## Build from source

Use Swift 6.2.1 or newer. The dependency graph is pinned by `Package.resolved`.

### Linux

```bash
sudo apt install clang libglib2.0-dev libgtk-4-dev libsqlite3-dev pkg-config
swift build --product CodexBarCross
.build/debug/CodexBarCross
```

For the release layout used by GitHub Actions:

```bash
swift build -c release --product CodexBarCross
bin_dir="$(swift build -c release --product CodexBarCross --show-bin-path)"
./Scripts/package_cross_platform_app.sh linux 0.0.0-dev x86_64 "$bin_dir" /tmp/codexbar-assets
```

### macOS

```bash
swift build -c release --product CodexBarCross --arch arm64
bin_dir="$(swift build -c release --product CodexBarCross --arch arm64 --show-bin-path)"
./Scripts/package_cross_platform_app.sh macos 0.0.0-dev arm64 "$bin_dir" /tmp/codexbar-assets
```

### Windows

Build from a Visual Studio developer shell with Swift 6.2.1, SQLite from vcpkg, and the Windows SDK available:

```powershell
vcpkg install sqlite3:x64-windows
swift build -c release --product CodexBarCross -j 2
$bin = swift build -c release --product CodexBarCross --show-bin-path
./Scripts/package_cross_platform_windows.ps1 `
    -Version 0.0.0-dev -Architecture x86_64 -BinDirectory $bin -OutputDirectory $env:TEMP
```

## Usage history and resource behavior

Usage & Spend uses the original Codex historical scanner and its SQLite cache. The first index is a progressive
historical catch-up. Automatic maintenance runs only after the configured refresh interval and gives each pass a
bounded 350 ms scan budget; subsequent passes prioritize changed or incomplete sessions and reuse persisted file
offsets and aggregates.

Opening Usage & Spend loads aggregate-only cached history. It does not hydrate every raw session row or synchronously
walk the whole archive. The partial-index banner is shown only while cache metadata says complete historical coverage
has not yet been established. Choosing **Refresh** is intentionally different: it drains bounded scanner passes until
the complete historical refresh succeeds or reports an actionable error.

The dashboard offers 7-day, 30-day, 90-day, and All ranges. The shared scanner currently requests and retains up to
365 days for this view. The cache lives under the platform's user cache directory in
`CodexBar/cost-usage/cost-usage.sqlite`; it uses the original schema, parser hash, checkpoints, and incremental scan
state.

## Renderer selection

On Linux, **Automatic** leaves GTK's renderer selection untouched, allowing GTK to use hardware acceleration when the
driver and session support it. **Low-memory software** sets `GSK_RENDERER=cairo` before GTK starts. It can reduce GPU
allocation on some systems but may make animation and resizing less fluid. An existing `GSK_RENDERER` environment
variable always takes precedence.

macOS and Windows use their native SwiftCrossUI backends and normal platform compositor behavior. Hardware
acceleration is opportunistic, not guaranteed for unsupported drivers, remote sessions, or software-rendered desktop
environments.

## Validation and releases

Run the portable packaging check and the repository test gates before pushing:

```bash
./Scripts/test_package_cross_platform_app.sh
make check
make test
```

`.github/workflows/cross-platform-app.yml` builds and smoke-tests Linux x86_64, macOS arm64, macOS x86_64, and
Windows x86_64. Branch builds are retained as workflow artifacts. A `v*-cross.*` tag publishes the same archives and
checksums as a prerelease in this fork. Cross tags are excluded from the upstream CLI/Homebrew release workflow.
