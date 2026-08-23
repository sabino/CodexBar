#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codexbar-cross-package-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

BIN_DIR="$TEMP_DIR/bin"
OUTPUT_DIR="$TEMP_DIR/output"
mkdir -p "$BIN_DIR/CodexBar_CodexBarCore.resources"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN_DIR/CodexBarCross"
chmod 0755 "$BIN_DIR/CodexBarCross"
printf '%s\n' "fixture" > "$BIN_DIR/CodexBar_CodexBarCore.resources/provider.js"

ASSET="$($ROOT_DIR/Scripts/package_cross_platform_app.sh \
  linux 0.0.0-test x86_64 "$BIN_DIR" "$OUTPUT_DIR" | tail -n1)"

[[ "$ASSET" == "$OUTPUT_DIR/CodexBarCross-v0.0.0-test-linux-x86_64.tar.gz" ]]
[[ -f "$ASSET" ]]
[[ -f "$ASSET.sha256" ]]
tar -tzf "$ASSET" | grep -Fx 'CodexBarCross/CodexBarCross'
tar -tzf "$ASSET" | grep -Fx 'CodexBarCross/CodexBar_CodexBarCore.resources/provider.js'
tar -tzf "$ASSET" | grep -Fx 'CodexBarCross/README.md'
tar -tzf "$ASSET" | grep -Fx 'CodexBarCross/VERSION'

echo "Cross-platform package tests passed."
