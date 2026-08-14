# CodexBar Native

CodexBar Native is the cross-platform Rust + Slint implementation. The UI and
application logic are shared by Linux, macOS, and Windows and compile to a
native executable. There is no Chromium, Node.js, Electron, or embedded WebView.

The native frontend consumes the same `CodexBarCore` provider engine as the
macOS app through a versioned JSON bridge. That keeps all 69 first-party and
plugin provider routes, credential sources, account selection, provider
status, credits, quota windows, pace data, and local cost history in one
canonical implementation instead of rewriting them in the UI language.

The shared frontend includes the provider switcher, quota cards, credits and
cost summaries, native tray menu, provider settings navigation, enable/disable
controls, and the 7/30-day Usage & Spend dashboard. See [`PARITY.md`](PARITY.md)
for the contract and visual acceptance rules.

## Why Slint

- One declarative `.slint` UI and one Rust application core on all three desktop
  operating systems.
- Native windows and system tray integration, with a software renderer and
  system fonts; no browser engine or JavaScript runtime ships with the app.
- A small release binary and low idle memory use compared with web-shell stacks.
- The UI boundary is declarative, while provider/network code remains ordinary
  testable Rust.

This app uses Slint under the royalty-free desktop application license. The
required `AboutSlint` attribution is available from the top-level tray menu, and
the license text is retained under [`LICENSES/`](LICENSES/).

## Build and test

Rust 1.93.1 is pinned in `rust-toolchain.toml`.

Ubuntu build packages:

```bash
sudo apt-get install build-essential pkg-config libfontconfig1-dev \
  libxkbcommon-dev libxkbcommon-x11-dev libwayland-dev
```

Then:

```bash
cd native
cargo test --locked
cargo run --locked -- --show
cargo build --release --locked
```

On macOS or Windows, the same three Cargo commands build the same source tree.
The GitHub Actions matrix compiles and tests all three operating systems.

## Install on Linux

The installer copies the release binary into `~/.local/bin`, installs a systemd
user service, adds an application-menu launcher, and starts the tray app:

```bash
cd native
./scripts/install-linux.sh
```

To install a release binary and an official or locally built provider engine:

```bash
./scripts/install-linux.sh \
  --binary ./target/release/codexbar-native \
  --engine /path/to/CodexBarCLI
```

`CodexBar_CodexBarCore.bundle` must be beside `CodexBarCLI`; official CLI
archives already have that layout. The installer copies both into
`~/.local/lib/codexbar-native` and points the user service at that engine.

The app uses the StatusNotifierItem tray protocol. GNOME, KDE, and similar
desktops normally support that directly. Regolith/i3 exposes an XEmbed tray, so
the installer enables `snixembed.service` when `~/.local/bin/snixembed` already
exists. This bridge is desktop integration, not an application runtime.

The installer also adds floating-window rules when it detects this laptop's
Regolith configuration directory. Those rules are isolated in
`~/.config/regolith3/i3/config.d/93-codexbar-native`.

Useful commands:

```bash
systemctl --user status codexbar-native.service
systemctl --user restart codexbar-native.service
journalctl --user -u codexbar-native.service
```

To remove the installed integration without touching Codex credentials:

```bash
systemctl --user disable --now codexbar-native.service snixembed.service
rm ~/.config/systemd/user/codexbar-native.service
rm ~/.config/systemd/user/snixembed.service
rm ~/.local/bin/codexbar-native ~/.local/bin/codexbar-native-show
rm -rf ~/.local/lib/codexbar-native
rm ~/.local/share/applications/codexbar-native.desktop
rm ~/.local/share/icons/hicolor/512x512/apps/codexbar-native.png
rm ~/.config/regolith3/i3/config.d/93-codexbar-native
systemctl --user daemon-reload
```

## Credentials and privacy

The provider engine reads the same redacted CodexBar configuration, browser
cookies, OAuth sessions, API keys, CLI logins, and local usage logs as the
macOS app. The native frontend receives display-safe JSON only; it never asks
the bridge to dump secrets. If the engine is unavailable, a deliberately
limited direct Codex OAuth fallback keeps Codex usage visible while reporting
that full provider parity is unavailable.

## Source layout

- `ui/app.slint`: shared details window, about dialog, and system tray menu.
- `src/main.rs`: UI callbacks, refresh scheduling, and presentation formatting.
- `src/engine.rs`: typed, additive bridge to the canonical CodexBarCLI engine.
- `src/icons.rs`: embedded provider artwork shared by all desktop targets.
- `src/codex.rs`: emergency direct-Codex fallback and parser tests.
- `packaging/linux`: systemd, desktop-entry, and Regolith integration templates.
- `scripts/install-linux.sh`: per-user Linux installer.
