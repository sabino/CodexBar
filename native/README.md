# CodexBar Native

CodexBar Native is the cross-platform Rust + Slint implementation. The UI and
application logic are shared by Linux, macOS, and Windows and compile to a
native executable. There is no Chromium, Node.js, Electron, or embedded WebView.

The current milestone is intentionally narrow: it reads an existing Codex CLI
OAuth login, shows session/weekly usage and reset times, refreshes credentials
when necessary, and exposes the result through a native system tray menu and a
small details window. The original macOS app remains the feature-complete
implementation for the other providers.

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

To install a release binary that is already built:

```bash
./scripts/install-linux.sh --binary ./target/release/codexbar-native
```

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
rm ~/.local/share/applications/codexbar-native.desktop
rm ~/.local/share/icons/hicolor/512x512/apps/codexbar-native.png
rm ~/.config/regolith3/i3/config.d/93-codexbar-native
systemctl --user daemon-reload
```

## Credentials and privacy

The native app reads the same `auth.json` used by the Codex CLI from
`$CODEX_HOME` or `~/.codex`. It never prints tokens. If the access token expires,
it uses the existing refresh token and atomically replaces `auth.json`; Unix
files are written with mode `0600`.

The usage request is made directly to the configured ChatGPT/Codex API. Set
`chatgpt_base_url` in the Codex config exactly as you would for the CLI.

## Source layout

- `ui/app.slint`: shared details window, about dialog, and system tray menu.
- `src/main.rs`: UI callbacks, refresh scheduling, and presentation formatting.
- `src/codex.rs`: Codex OAuth loading, refresh, usage parsing, and tests.
- `packaging/linux`: systemd, desktop-entry, and Regolith integration templates.
- `scripts/install-linux.sh`: per-user Linux installer.
