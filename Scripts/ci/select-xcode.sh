#!/usr/bin/env bash
# Xcode seçimi (macOS runner). macOS'taki /bin/bash 3.2 ile uyumludur.
# Kullanım: select-xcode.sh [istek]
#   istek boş   -> XCODE_MAJOR (varsayılan 26) serisinin en yeni KARARLI sürümü
#   "26.5"      -> 26.5 veya 26.5.x'in en yenisi
#   tam yol     -> /Applications/Xcode_26.5.app
set -euo pipefail

REQ="${1:-}"
PREFIX="${REQ:-${XCODE_MAJOR:-26}}"
PICK=""

case "$REQ" in
  /Applications/*.app) PICK="$REQ" ;;
  *)
    BEST_KEY=""
    for APP in /Applications/Xcode_*.app; do
      [ -d "$APP" ] || continue
      [ -L "$APP" ] && continue                       # Xcode_26.6.0.app gibi symlink'leri atla
      VER="${APP#/Applications/Xcode_}"; VER="${VER%.app}"
      [[ "$VER" =~ ^[0-9]+(\.[0-9]+)*$ ]] || continue # beta / RC / "_beta_3" adlarını atla
      [[ "$VER" == "$PREFIX" || "$VER" == "$PREFIX".* ]] || continue
      IFS=. read -r MA MI PA <<< "$VER"
      KEY=$(printf '%03d%03d%03d' "$((10#${MA:-0}))" "$((10#${MI:-0}))" "$((10#${PA:-0}))")
      if [[ -z "$BEST_KEY" || "$KEY" > "$BEST_KEY" ]]; then
        BEST_KEY="$KEY"; PICK="$APP"
      fi
    done
    ;;
esac

if [ -z "$PICK" ] || [ ! -d "$PICK" ]; then
  echo "::error::Uygun Xcode bulunamadı (istek: '$PREFIX'). Kurulu olanlar:"
  ls -d /Applications/Xcode* || true
  exit 1
fi

sudo xcode-select -s "$PICK/Contents/Developer"
echo "DEVELOPER_DIR=$PICK/Contents/Developer" >> "$GITHUB_ENV"
echo "Seçilen: $PICK"
xcodebuild -version
echo "iOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)"
swift --version
{
  echo "### Derleme ortamı"
  echo "- Xcode: $(xcodebuild -version | tr '\n' ' ')"
  echo "- iOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)"
  echo "- Swift: $(swift --version 2>&1 | head -n 1)"
} >> "$GITHUB_STEP_SUMMARY"
