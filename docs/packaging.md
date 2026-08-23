---
summary: "Packaging native cross-platform archives and the signed original macOS app."
read_when:
  - Packaging/signing builds
  - Updating bundle layout or CLI bundling
  - Publishing CodexBarCross artifacts
---

# Packaging & signing

## Scripts
- `Scripts/package_cross_platform_app.sh`: stages Linux tarballs or ad-hoc-signed macOS app bundles from an existing
  `CodexBarCross` release build and emits a SHA-256 checksum.
- `Scripts/package_cross_platform_windows.ps1`: stages the Windows executable, Swift runtime, SQLite DLLs, resources,
  documentation, and checksum.
- `Scripts/test_package_cross_platform_app.sh`: validates the portable Linux archive contract without a full build.
- `Scripts/package_app.sh`: builds host arch with ad-hoc signing by default; set `ARCHES="arm64 x86_64"` for universal. Verifies slices. Stable-certificate packaging requires explicit `CODEXBAR_SIGNING=identity` plus `APP_IDENTITY`.
- `Scripts/compile_and_run.sh`: uses host arch; pass `--release-universal` or `--release-arches="arm64 x86_64"` for release packaging.
- `Scripts/sign-and-notarize.sh`: explicitly selects Developer ID signing, notarizes, staples, and zips (accepts `ARCHES` for universal).
- `Scripts/make_appcast.sh`: wrapper around the shared `mac-release make-appcast` helper; app metadata comes from `.mac-release.env`.
- `Scripts/changelog-to-html.sh`: converts the per-version changelog section to HTML for Sparkle.

## Bundle contents

### Cross-platform desktop

- Linux archives contain a stripped `CodexBarCross`, its required Swift runtime libraries, the `CodexBarCore` SwiftPM
  resource bundle, license, version, and runtime guide. GTK/GLib/SQLite remain host libraries.
- macOS archives contain a minimal `CodexBarCross.app` with the same resource payload and an ad-hoc signature. These
  fork artifacts are not notarized and do not include Sparkle or WidgetKit.
- Windows archives contain `CodexBarCross.exe`, all SwiftPM resources, Swift runtime DLLs, and vcpkg runtime DLLs.
  Windows App Runtime remains a machine prerequisite.

### Original macOS app

- `CodexBarWidget.appex` is built by `WidgetExtension/CodexBarWidgetExtension.xcodeproj` as a real macOS app extension, then bundled with app-group entitlements.
- `CodexBarCLI` copied to `CodexBar.app/Contents/Helpers/` for symlinking.
- SwiftPM resource bundles (e.g. `KeyboardShortcuts_KeyboardShortcuts.bundle`) copied into `Contents/Resources` (required for `KeyboardShortcuts.Recorder`).

## Releases
- `.github/workflows/cross-platform-app.yml` builds and smoke-tests all supported native desktop assets. A
  `v*-cross.*` tag publishes them as a fork prerelease.
- The original signed macOS app follows the full checklist in `docs/RELEASING.md`.

See also: `docs/CROSS_PLATFORM.md`, `docs/sparkle.md`.
