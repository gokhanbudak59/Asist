#!/usr/bin/env bash
# XcodeGen'i sabit sürüm + SHA256 doğrulamasıyla kurar (Homebrew'a bağımlı değil).
set -euo pipefail

VER="${XCODEGEN_VERSION:-2.46.0}"
SHA="${XCODEGEN_SHA256:-4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806}"
DEST="${RUNNER_TEMP:-/tmp}/xcodegen-$VER"
BIN="$DEST/xcodegen/bin/xcodegen"

if [ ! -x "$BIN" ]; then
  mkdir -p "$DEST"
  curl -fsSL --retry 3 -o "$DEST/xcodegen.zip" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$VER/xcodegen.zip"
  echo "$SHA  $DEST/xcodegen.zip" | shasum -a 256 -c -
  unzip -q -o "$DEST/xcodegen.zip" -d "$DEST"
fi

# İkili, SettingPresets'i <bin>/../share/xcodegen altında bulur; zip bu düzeni korur.
test -d "$DEST/xcodegen/share/xcodegen/SettingPresets" || {
  echo "::error::XcodeGen SettingPresets eksik"; exit 1; }

echo "$DEST/xcodegen/bin" >> "$GITHUB_PATH"
"$BIN" --version
