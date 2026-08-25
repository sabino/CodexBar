# Native parity contract

The native application is a shared Rust + Slint frontend for Linux, macOS, and
Windows. It does not duplicate provider logic. `CodexBarCore`, reached through
the packaged `CodexBarCLI` engine, remains the canonical implementation for
provider discovery, credentials, fetch routing, status, account selection,
usage presentation, local cost scanning, and history.

## Invariants

- One provider engine: every first-party and plugin provider is fetched by the
  same `CodexBarCore` code used by the macOS app.
- One visual system: all controls in the Slint frontend are custom components;
  platform widget themes are not allowed to change spacing, color, typography,
  or interaction states.
- Additive protocol: the frontend consumes the stable dashboard-v1, provider
  catalog, and cost JSON payloads. New fields are optional so a newer frontend
  can still run with the previous engine release.
- No browser runtime: dashboards may be opened in the user's browser, but no
  Electron, webview, HTML UI, or JavaScript renderer is embedded in the app.
- No secret projection: engine JSON contains display identity and provider
  state, never raw tokens, cookies, or config secrets.
- Last-good state: a failed refresh must not erase the last successful provider
  snapshot or history.

## Engine projections

| Native surface | Canonical engine projection |
| --- | --- |
| Provider switcher and menu cards | `dashboard --identity full` |
| All provider names and enablement | `config providers --json` |
| Enable/disable provider | `config enable/disable --provider` |
| Daily/model/project cost history | `cost --provider all --json --days 30` |
| Provider-specific detail rows/charts | additive dashboard `details` field |
| Pace and quota forecast | additive dashboard `pace` field |
| Provider links and capabilities | additive provider-catalog metadata |

The bridge first looks for `CODEXBAR_ENGINE`, then a helper beside the native
binary, then `~/.local/lib/codexbar-native/CodexBarCLI`, and finally
`CodexBarCLI`/`codexbar` on `PATH`.

## Visual acceptance

Parity is measured against the checked-in macOS references in
`docs/screenshots/` at fixed light and dark viewports. Fixtures must cover every
provider plus loading, empty, error, stale, multi-account, extra-window,
credits-only, and cost-history states. SF Pro and SF Symbols are used only where
the operating system licenses and supplies them; bundled open fonts/icons keep
the same metrics and geometry elsewhere.

## Packaging

The current compatibility package contains two native executables: the small
Rust/Slint frontend and the Swift provider engine. This deliberately trades
package size for exact provider behavior. The JSON boundary allows a later
static-library or Rust-core engine without changing the shared UI.
