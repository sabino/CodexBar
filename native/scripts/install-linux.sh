#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s [--binary PATH] [--engine PATH] [--no-start]\n' "${0##*/}"
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
native_dir="$(cd -- "${script_dir}/.." && pwd)"
repo_dir="$(cd -- "${native_dir}/.." && pwd)"
binary_path=""
engine_path=""
start_services=1

while (($#)); do
    case "$1" in
        --binary)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            binary_path="$2"
            shift 2
            ;;
        --engine)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            engine_path="$2"
            shift 2
            ;;
        --no-start)
            start_services=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

[[ "$(uname -s)" == "Linux" ]] || {
    printf 'This installer is for Linux. Build with Cargo directly on macOS or Windows.\n' >&2
    exit 1
}

if [[ -z "$binary_path" ]]; then
    cargo build --manifest-path "${native_dir}/Cargo.toml" --release --locked
    binary_path="${native_dir}/target/release/codexbar-native"
fi
binary_path="$(realpath "$binary_path")"
[[ -x "$binary_path" ]] || {
    printf 'Native binary is missing or not executable: %s\n' "$binary_path" >&2
    exit 1
}

if [[ -z "$engine_path" && -n "${CODEXBAR_ENGINE:-}" ]]; then
    engine_path="$CODEXBAR_ENGINE"
fi
if [[ -z "$engine_path" ]]; then
    binary_dir="$(dirname -- "$binary_path")"
    for candidate in \
        "${binary_dir}/CodexBarCLI" \
        "${repo_dir}/.build/release/CodexBarCLI" \
        "$(command -v CodexBarCLI 2>/dev/null || true)" \
        "$(command -v codexbar 2>/dev/null || true)"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            engine_path="$candidate"
            break
        fi
    done
fi
[[ -n "$engine_path" ]] || {
    printf '%s\n' \
        'The CodexBarCLI provider engine is required for full provider parity.' \
        'Pass --engine PATH from an official CodexBar CLI archive or a local release build.' >&2
    exit 1
}
engine_path="$(realpath "$engine_path")"
[[ -x "$engine_path" ]] || {
    printf 'Provider engine is missing or not executable: %s\n' "$engine_path" >&2
    exit 1
}
engine_source_dir="$(dirname -- "$engine_path")"
engine_bundle="${engine_source_dir}/CodexBar_CodexBarCore.bundle"
[[ -d "$engine_bundle" ]] || {
    printf 'Provider resource bundle is missing beside the engine: %s\n' "$engine_bundle" >&2
    exit 1
}

bin_dir="${HOME}/.local/bin"
data_home="${XDG_DATA_HOME:-${HOME}/.local/share}"
config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
unit_dir="${config_home}/systemd/user"
application_dir="${data_home}/applications"
icon_dir="${data_home}/icons/hicolor/512x512/apps"
engine_install_dir="${HOME}/.local/lib/codexbar-native"

install -Dm755 "$binary_path" "${bin_dir}/codexbar-native"
install -d -m 0755 "$engine_install_dir"
install -m 0755 "$engine_path" "${engine_install_dir}/CodexBarCLI"
rm -rf -- "${engine_install_dir}/CodexBar_CodexBarCore.bundle"
cp -a -- "$engine_bundle" "${engine_install_dir}/CodexBar_CodexBarCore.bundle"
if [[ -f "${engine_source_dir}/VERSION" ]]; then
    install -m 0644 "${engine_source_dir}/VERSION" "${engine_install_dir}/VERSION"
fi
install -Dm755 "${native_dir}/packaging/linux/codexbar-native-show" \
    "${bin_dir}/codexbar-native-show"
install -Dm644 "${native_dir}/packaging/linux/codexbar-native.service" \
    "${unit_dir}/codexbar-native.service"
install -Dm644 "${repo_dir}/docs/icon.png" \
    "${icon_dir}/codexbar-native.png"

desktop_file="${application_dir}/codexbar-native.desktop"
install -d "$application_dir"
sed "s|@SHOW_HELPER@|${bin_dir}/codexbar-native-show|g" \
    "${native_dir}/packaging/linux/codexbar-native.desktop.in" > "$desktop_file"
chmod 0644 "$desktop_file"

regolith_config_dir="${config_home}/regolith3/i3/config.d"
if [[ -d "$regolith_config_dir" ]]; then
    install -Dm644 "${native_dir}/packaging/linux/regolith-codexbar.conf" \
        "${regolith_config_dir}/93-codexbar-native"
fi

enable_snixembed=0
if [[ -x "${bin_dir}/snixembed" && "${XDG_CURRENT_DESKTOP:-}" == *Regolith* ]]; then
    install -Dm644 "${native_dir}/packaging/linux/snixembed.service" \
        "${unit_dir}/snixembed.service"
    enable_snixembed=1
fi

systemctl --user daemon-reload

environment_names=()
for name in DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS XDG_CURRENT_DESKTOP; do
    if [[ -n "${!name:-}" ]]; then
        environment_names+=("$name")
    fi
done
if ((${#environment_names[@]})); then
    systemctl --user import-environment "${environment_names[@]}"
fi

if ((start_services)); then
    if ((enable_snixembed)); then
        systemctl --user enable --now snixembed.service
    fi
    systemctl --user enable --now codexbar-native.service
fi

if [[ -d "$regolith_config_dir" ]] && command -v i3-msg >/dev/null 2>&1; then
    i3-msg reload >/dev/null
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$application_dir" >/dev/null 2>&1 || true
fi

printf 'Installed CodexBar Native to %s\n' "${bin_dir}/codexbar-native"
printf 'Installed the canonical provider engine to %s\n' "${engine_install_dir}/CodexBarCLI"
if ((start_services)); then
    printf 'The tray service is enabled and running for this user.\n'
else
    printf 'Start it with: systemctl --user enable --now codexbar-native.service\n'
fi
