#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 5 ]]; then
  echo "Usage: $(basename "$0") <linux|macos> <version> <architecture> <swift-bin-dir> <output-dir>" >&2
  exit 2
fi

PLATFORM="$1"
VERSION="$2"
ARCHITECTURE="$3"
BIN_DIR="$4"
OUTPUT_DIR="$5"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! "$VERSION" =~ ^[0-9A-Za-z._-]+$ ]]; then
  echo "Invalid package version: $VERSION" >&2
  exit 2
fi
if [[ ! "$ARCHITECTURE" =~ ^[0-9A-Za-z._-]+$ ]]; then
  echo "Invalid architecture: $ARCHITECTURE" >&2
  exit 2
fi
if [[ ! -x "$BIN_DIR/CodexBarCross" ]]; then
  echo "Missing CodexBarCross executable: $BIN_DIR/CodexBarCross" >&2
  exit 1
fi

resolve_core_resources() {
  local candidate
  for candidate in \
    "$BIN_DIR/CodexBar_CodexBarCore.bundle" \
    "$BIN_DIR/CodexBar_CodexBarCore.resources"; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  echo "Missing CodexBarCore resource bundle in $BIN_DIR" >&2
  return 1
}

strip_staged_executable() {
  local executable="$1"
  local format
  command -v file >/dev/null 2>&1 || return 0
  format="$(file -b "$executable")"
  case "$format" in
    *ELF*)
      command -v strip >/dev/null 2>&1 || {
        echo "strip is required to package an ELF release executable" >&2
        return 1
      }
      strip --strip-unneeded "$executable"
      ;;
    *Mach-O*)
      command -v strip >/dev/null 2>&1 || {
        echo "strip is required to package a Mach-O release executable" >&2
        return 1
      }
      strip -x "$executable"
      ;;
  esac
}

package_linux_swift_runtime() {
  local executable="$1"
  local package_root="$2"
  local copied=0
  local resolved
  command -v ldd >/dev/null 2>&1 || {
    echo "ldd is required to resolve the Linux Swift runtime" >&2
    return 1
  }
  while IFS= read -r resolved; do
    [[ -f "$resolved" ]] || continue
    case "$resolved" in
      */swift/linux/*.so)
        cp -L "$resolved" "$package_root/$(basename "$resolved")"
        strip_staged_executable "$package_root/$(basename "$resolved")"
        copied=$((copied + 1))
        ;;
    esac
  done < <(ldd "$executable" | awk '$2 == "=>" && $3 ~ /^\// { print $3 }')
  if [[ "$copied" -eq 0 ]]; then
    echo "No dynamically linked Swift runtime libraries were found for $executable" >&2
    return 1
  fi
}

mkdir -p "$OUTPUT_DIR"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codexbar-cross-package.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
CORE_RESOURCES="$(resolve_core_resources)"
BUNDLE_VERSION="${VERSION%%-*}"

case "$PLATFORM" in
  linux)
    PACKAGE_ROOT="$STAGE_DIR/CodexBarCross"
    mkdir -p "$PACKAGE_ROOT"
    install -m 0755 "$BIN_DIR/CodexBarCross" "$PACKAGE_ROOT/CodexBarCross"
    strip_staged_executable "$PACKAGE_ROOT/CodexBarCross"
    if file -b "$PACKAGE_ROOT/CodexBarCross" | grep -q 'ELF'; then
      package_linux_swift_runtime "$PACKAGE_ROOT/CodexBarCross" "$PACKAGE_ROOT"
    fi
    cp -R "$CORE_RESOURCES" "$PACKAGE_ROOT/$(basename "$CORE_RESOURCES")"
    install -m 0644 "$ROOT_DIR/LICENSE" "$PACKAGE_ROOT/LICENSE"
    install -m 0644 "$ROOT_DIR/docs/CROSS_PLATFORM.md" "$PACKAGE_ROOT/README.md"
    printf '%s\n' "$VERSION" > "$PACKAGE_ROOT/VERSION"

    ASSET="CodexBarCross-v${VERSION}-linux-${ARCHITECTURE}.tar.gz"
    tar -C "$STAGE_DIR" -czf "$OUTPUT_DIR/$ASSET" CodexBarCross
    ;;
  macos)
    APP_ROOT="$STAGE_DIR/CodexBarCross.app"
    CONTENTS="$APP_ROOT/Contents"
    mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
    install -m 0755 "$BIN_DIR/CodexBarCross" "$CONTENTS/MacOS/CodexBarCross"
    strip_staged_executable "$CONTENTS/MacOS/CodexBarCross"
    cp -R "$CORE_RESOURCES" "$CONTENTS/Resources/CodexBar_CodexBarCore.bundle"
    install -m 0644 "$ROOT_DIR/Icon.icns" "$CONTENTS/Resources/Icon.icns"
    install -m 0644 "$ROOT_DIR/docs/CROSS_PLATFORM.md" "$CONTENTS/Resources/README.md"
    cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>CodexBar Cross</string>
    <key>CFBundleExecutable</key><string>CodexBarCross</string>
    <key>CFBundleIconFile</key><string>Icon</string>
    <key>CFBundleIdentifier</key><string>com.sabino.codexbar.cross</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>CodexBarCross</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${BUNDLE_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUNDLE_VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
    plutil -lint "$CONTENTS/Info.plist"
    codesign --force --deep --sign - "$APP_ROOT"
    codesign --verify --deep --strict --verbose=2 "$APP_ROOT"

    ASSET="CodexBarCross-v${VERSION}-macos-${ARCHITECTURE}.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP_ROOT" "$OUTPUT_DIR/$ASSET"
    ;;
  *)
    echo "Unsupported package platform: $PLATFORM" >&2
    exit 2
    ;;
esac

"$ROOT_DIR/Scripts/generate_release_checksum.sh" "$OUTPUT_DIR/$ASSET"
printf '%s\n' "$OUTPUT_DIR/$ASSET"
