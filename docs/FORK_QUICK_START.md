---
summary: "Quick commands and boundaries for the sabino/CodexBar native cross-platform fork."
read_when:
  - Onboarding to this fork
  - Building the portable Swift desktop app
  - Choosing between fork and upstream release workflows
---

# Fork quick start

This is `sabino/CodexBar`, a fork of `steipete/CodexBar`. It tracks the original macOS app and CLI while adding
`CodexBarCross`, a native SwiftCrossUI app for Linux, macOS, and Windows. Provider and historical-usage behavior stays
in the shared `CodexBarCore`; the fork does not maintain a Rust or Electron implementation.

## Build and run

```bash
# Native cross-platform desktop app
swift build --product CodexBarCross
swift run CodexBarCross

# Original macOS bundle
./Scripts/compile_and_run.sh --test

# Repository gates
make check
make test
```

Linux needs Clang, GTK 4/GLib, SQLite development headers, and `pkg-config`. Windows needs Swift, Visual Studio, SQLite
from vcpkg, and the Windows App Runtime. See [Cross-platform desktop app](CROSS_PLATFORM.md) for exact setup and
packaging commands.

## Source map

- `Sources/CodexBarCore`: provider registry, fetchers, parsers, config, status, cost, and history.
- `Sources/CodexBarCross`: compact window, settings, Usage & Spend, provider artwork, and shared view tree.
- `Sources/CodexBarCrossSupport`: portable state and performance seams.
- `Sources/CPlatformTray`: native Linux/macOS/Windows tray shim.
- `Sources/CodexBar`: original SwiftUI/AppKit macOS app.
- `TestsLinux`: shared core and portable-app tests that run on Linux.

## Release

Cross-platform releases are fork prereleases tagged `v<upstream-version>-cross.<revision>`. The
`cross-platform-app.yml` workflow builds Linux x86_64, macOS arm64/x86_64, and Windows x86_64 executables and publishes
archives plus checksums. The original signed/notarized macOS release remains a separate upstream-compatible process.

Do not create an upstream pull request as part of a fork release. See [Release process](RELEASING.md) and
[Upstream strategy](UPSTREAM_STRATEGY.md).
