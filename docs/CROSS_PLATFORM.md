---
summary: "Build, install, and maintain the CodexBar Native SwiftCrossUI app for Linux and macOS."
read_when:
  - Building or installing CodexBarCross
  - Debugging its tray, renderer, settings, or usage history
  - Publishing cross-platform desktop release assets
---

# CodexBar Native desktop app

[`sabino/CodexBar-Native`](https://github.com/sabino/CodexBar-Native) is the native cross-platform fork of
`steipete/CodexBar`. Its `CodexBarCross` executable keeps provider parsing, authentication sources, quota models,
pricing, and historical usage in the same `CodexBarCore` used by the original CodexBar app and CLI. Linux and macOS
releases render one SwiftCrossUI view tree; the Windows backend remains in the same source tree as an unreleased
preview. Only the window, tray, and native-control adapters vary by platform.

The original SwiftUI/AppKit app under `Sources/CodexBar` remains the canonical signed and notarized macOS product.
The cross-platform app is a second executable, not a rewrite of provider logic and not an Electron or Rust shell.

## What is shared

- The provider registry, fetchers, parsers, usage snapshots, account metadata, status probes, and dashboard links come
  from `CodexBarCore`.
- The compact provider window, full settings window, provider search, Usage & Spend dashboard, custom provider icons,
  and tray menu use one Swift implementation under `Sources/CodexBarCross`.
- `CPlatformTray` supplies `NSStatusItem` on macOS, `Shell_NotifyIcon` on Windows, and StatusNotifierItem over D-Bus on
  Linux.
- `CodexBarCrossSupport` contains renderer-neutral navigation, history-loading, history-coverage, and presentation
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

Each archive has a matching `.sha256` file. Download releases from
<https://github.com/sabino/CodexBar-Native/releases>.

### Linux

Install the GTK 4, GLib/GIO, and SQLite runtime libraries. On Ubuntu 24.04:

```bash
sudo apt install libgtk-4-1 libglib2.0-0 libsqlite3-0
tar -xzf CodexBarCross-v*-linux-x86_64.tar.gz
./CodexBarCross/CodexBarCross
```

The tray implementation uses StatusNotifierItem plus the standard D-Bus menu protocol. Left click toggles the compact
window; right click exposes Show, Refresh, Settings, About, and Quit through the host panel's native menu. KDE, modern
GNOME extensions, and compatible panels can host it directly. An XEmbed-only panel, including some i3 bars, needs a
bridge such as `snixembed`. Escape hides the compact window; the custom close button does the same without relying on
window-manager decorations.

### macOS

Extract with `ditto`, then open the app:

```bash
ditto -x -k CodexBarCross-v*-macos-arm64.zip .
open CodexBarCross.app
```

Fork builds are ad-hoc signed for reproducible CI packaging and are not notarized. Gatekeeper may require an explicit
Open action. Use the original CodexBar release when Developer ID signing, notarization, Sparkle updates, WidgetKit, or
the complete macOS integration set is required.

### Windows source preview

Windows release archives are deferred. The WinUI backend, tray shim, host compatibility layer, and packaging script
remain available for source builds, but Windows is not currently a release gate. Ordinary provider helper commands
launch through native `Foundation.Process`; Unix PTY-only CLI interactions fail soft when a provider has no API,
OAuth, config-file, or non-interactive command fallback on Windows.

## Build from source

Use Swift 6.2.1 or newer. The patched SwiftCrossUI renderer source is vendored at its documented upstream revision,
and the root package's remote dependencies are locked by `Package.resolved`. The `CrossPlatformApp` package trait
enables only the native renderer graph; leaving it off keeps the original `CodexBarCLI` and `CodexBarCore` builds free
of GTK, AppKitBackend, and WinUI build dependencies.

### Linux

```bash
sudo apt install clang libglib2.0-dev libgtk-4-dev libsqlite3-dev pkg-config
swift build --traits CrossPlatformApp --product CodexBarCross
.build/debug/CodexBarCross
```

For the release layout used by GitHub Actions:

```bash
swift build -c release --traits CrossPlatformApp --product CodexBarCross
bin_dir="$(swift build -c release --traits CrossPlatformApp --product CodexBarCross --show-bin-path)"
./Scripts/package_cross_platform_app.sh linux 0.0.0-dev x86_64 "$bin_dir" /tmp/codexbar-assets
```

### macOS

```bash
swift build -c release --traits CrossPlatformApp --product CodexBarCross --arch arm64
bin_dir="$(swift build -c release --traits CrossPlatformApp --product CodexBarCross --arch arm64 --show-bin-path)"
./Scripts/package_cross_platform_app.sh macos 0.0.0-dev arm64 "$bin_dir" /tmp/codexbar-assets
```

### Windows source preview

Build from a Visual Studio developer shell with Swift 6.2.1, SQLite from vcpkg, and the Windows SDK available:

```powershell
vcpkg install sqlite3:x64-windows
swift build -c release --traits CrossPlatformApp --product CodexBarCross -j 2
$bin = swift build -c release --traits CrossPlatformApp --product CodexBarCross --show-bin-path
./Scripts/package_cross_platform_windows.ps1 `
    -Version 0.0.0-dev -Architecture x86_64 -BinDirectory $bin -OutputDirectory $env:TEMP
```

## Usage history and resource behavior

Usage & Spend uses the original Codex historical scanner and its SQLite cache. The first index is a progressive
historical catch-up. Automatic maintenance runs on the configured refresh schedule and uses the scanner's bounded
incremental passes; subsequent passes prioritize changed or incomplete sessions and reuse persisted file offsets and
aggregates. This scheduling is background archive maintenance, not an input, layout, rendering, or navigation
throttle.

Opening Usage & Spend loads aggregate-only cached history. It does not hydrate every raw session row or synchronously
walk the whole archive. The partial-index banner appears only when both the snapshot lacks established coverage and a
current scanner status explicitly reports pending work; stale cache metadata alone cannot show it. Choosing
**Refresh** is intentionally different: it bypasses debounce, time limits, per-file and per-pass byte limits, and
candidate paging. It drains the scanner with no inter-pass delay until the complete historical refresh succeeds or
reports an actionable error. A fully read malformed tail or fork whose parent lineage is unavailable remains
fail-closed: the UI reports the unresolved session and deferred-line counts, and a timestamp-only cache rewrite is not
treated as progress or retried in a loop. Cancellation checks remain active; automatic maintenance stays incremental
and bounded.

The dashboard offers 7-day, 30-day, 90-day, and All ranges. The shared scanner currently requests and retains up to
365 days for this view. The cache lives under the platform's user cache directory in
`CodexBar/cost-usage/cost-usage.sqlite`; it uses the original schema, parser hash, checkpoints, and incremental scan
state.

CodexBar does not recursively crawl arbitrary disks, enumerate mounts, or discover SSH hosts. History readers inspect
the small provider-defined set of config, credential, browser, and session locations needed by enabled sources. The
Codex scanner walks only known Codex session roots. This frontend does not inspect the process list; browser storage is
read only when the selected provider source enables it. Platform-owned helpers can still trigger normal operating
system permission prompts when a user enables a source that requires them.

## Window and input responsiveness

The compact and settings roots consume the native window's full allocation, including live i3 floating and tiling
resizes. Resize, pointer, picker, toggle, navigation, and content-change events are delivered immediately: there is no
debounce, coalescer, cooldown, delayed latest-value queue, frame limiter, or low-power multiplier in the portable UI.
Card decoration is painted behind native controls so the controls remain the pointer targets.

On Linux, closing Settings destroys that window's renderer graph and native surfaces; reopening Settings reconstructs
it from the shared model. The compact tray window remains retained so tray activation stays immediate.

## Renderer selection

**Surface style** controls application paint independently of compositor transparency. Automatic uses layered surfaces
on macOS and fully opaque solid surfaces elsewhere; Solid is always opaque; Layered keeps the subtle tonal layering
without depending on desktop blur or transparency.

On Linux, the **Automatic** UI renderer leaves GTK's renderer selection untouched, allowing GTK to use hardware
acceleration when the driver and session support it. **Low-memory software** sets `GSK_RENDERER=cairo` before GTK
starts. It can reduce GPU allocation on some systems but may make rendering and resizing less fluid. An existing
`GSK_RENDERER` environment variable always takes precedence.

macOS uses its native SwiftCrossUI backend and normal platform compositor behavior. The unreleased Windows preview
does the same through WinUI. Hardware acceleration is opportunistic, not guaranteed for unsupported drivers, remote
sessions, or software-rendered desktop environments.

### Verified Linux performance envelope

The current release build was measured on Regolith/i3 over X11 with GTK 4, Swift 6.3.3, and an NVIDIA EGL renderer.
These numbers are a reproducible reference point, not a guarantee for every driver or provider set:

- settled tray/compact-window CPU: `0.00%` across five one-second `pidstat` samples;
- compact window memory: about 211 MB RSS, 157 MB proportional set size, and 42 MB anonymous memory;
- 1200×800 to 900×620 live resize: approximately 100–117 ms to exact final pixels in a 60 fps capture;
- settings route change: approximately 167 ms to exact final pixels;
- Linux release archive: about 35 MB, containing a stripped 33.7 MB executable plus Swift runtime libraries.

RSS includes mapped GTK, Swift, Foundation/ICU, graphics-driver, and other shared libraries, so proportional and
anonymous memory are the useful process-cost comparisons. Opening Settings creates a larger native widget graph;
closing it destroys that graph and its surfaces, although process and driver caches may remain warm. The renderer
performs no periodic UI polling, and settled idle CPU remains zero.

## Validation and releases

Run the portable packaging check and the repository test gates before pushing:

```bash
./Scripts/test_package_cross_platform_app.sh
make check
make test
```

`.github/workflows/cross-platform-app.yml` builds and smoke-tests Linux x86_64 plus macOS arm64 and x86_64. Branch
builds are retained as workflow artifacts. A `v*-cross.*` tag publishes those three archives and checksums as a
prerelease in this fork. The Windows job is intentionally disabled until that toolchain is ready to become a release
gate again. Cross tags are excluded from the upstream CLI/Homebrew release workflow.
