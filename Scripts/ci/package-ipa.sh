#!/usr/bin/env bash
# v1.0 (single target, no extension, no entitlements) — 04 §7.5.
# Asist.app -> two IPAs:
#   Asist.ipa          : ad-hoc signed (no entitlements in v1.0); Sideloadly re-signs it.
#   Asist-imzasiz.ipa  : completely unsigned fallback.
# Usage: package-ipa.sh <.../Release-iphoneos/Asist.app> <output dir>
set -euo pipefail

APP_SRC="$1"
OUT="$2"
APP_NAME="$(basename "$APP_SRC")"                       # Asist.app
EXE_NAME="${APP_NAME%.app}"                             # Asist

fail() { echo "::error::$*"; exit 1; }

# --- Pre-validation ---------------------------------------------------------
[ -d "$APP_SRC" ]                 || fail "Uygulama paketi yok: $APP_SRC"
[ -f "$APP_SRC/$EXE_NAME" ]       || fail "Çalıştırılabilir dosya yok: $APP_SRC/$EXE_NAME"
[ -f "$APP_SRC/Assets.car" ]      || fail "Derlenmiş asset kataloğu (Assets.car) yok"
if [ -d "$APP_SRC/PlugIns" ]; then
  echo "::warning::v1.0'da uzantı beklenmiyordu: $APP_SRC/PlugIns"
fi

PB=/usr/libexec/PlistBuddy
APP_ID=$($PB -c 'Print :CFBundleIdentifier' "$APP_SRC/Info.plist")
APP_VER=$($PB -c 'Print :CFBundleVersion' "$APP_SRC/Info.plist")
SHORT=$($PB -c 'Print :CFBundleShortVersionString' "$APP_SRC/Info.plist")
ARCHS="$(lipo -archs "$APP_SRC/$EXE_NAME")"
[[ "$ARCHS" == *arm64* ]] || fail "arm64 dilimi yok (bulunan: $ARCHS)"

# App Intents metadata (05a #30): if it is missing, Siri/Shortcuts silently lose Asist's actions.
# Reported as an error annotation but does not stop packaging.
META="$APP_SRC/Metadata.appintents/extract.actionsdata"
INTENTS_OK="evet"
if [ -f "$META" ]; then
  for NAME in KaydetIntent DinleIntent BugunIntent GecikenlerIntent; do
    if ! grep -q "$NAME" "$META"; then
      echo "::error::App Intents metadata içinde $NAME yok"
      INTENTS_OK="hayır"
    fi
  done
else
  echo "::error::App Intents metadata yok: $META"
  INTENTS_OK="hayır"
fi

# Notification sounds (D37): a missing file only falls back to the default sound.
for SND in asist-onemli.wav asist-kritik.wav; do
  if [ ! -f "$APP_SRC/$SND" ]; then
    echo "::warning::Bildirim sesi pakette yok: $SND"
  fi
done

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d)"

make_ipa() {  # $1 = staging dir (contains Payload/), $2 = ipa path
  rm -f "$2"
  (cd "$1" && zip -qry -X "$2" Payload)
  # `unzip | grep -q` under pipefail can fail with SIGPIPE (141) -> write the listing to a file first.
  unzip -Z1 "$2" > "$WORK/liste.txt"
  grep -q "^Payload/$APP_NAME/$EXE_NAME\$" "$WORK/liste.txt" || fail "IPA içinde çalıştırılabilir yok: $2"
}

# --- 1) Fallback: completely unsigned ----------------------------------------
mkdir -p "$WORK/plain/Payload"
ditto "$APP_SRC" "$WORK/plain/Payload/$APP_NAME"
make_ipa "$WORK/plain" "$OUT/Asist-imzasiz.ipa"

# --- 2) Main: ad-hoc signature (v1.0 embeds no entitlements) -----------------
mkdir -p "$WORK/signed/Payload"
ditto "$APP_SRC" "$WORK/signed/Payload/$APP_NAME"
codesign --force --sign - --timestamp=none "$WORK/signed/Payload/$APP_NAME"
make_ipa "$WORK/signed" "$OUT/Asist.ipa"

# --- Summary -------------------------------------------------------------------
{
  echo "### IPA"
  echo "| Dosya | Boyut | SHA-256 |"
  echo "|---|---|---|"
  for F in "$OUT/Asist.ipa" "$OUT/Asist-imzasiz.ipa"; do
    echo "| $(basename "$F") | $(du -h "$F" | cut -f1) | \`$(shasum -a 256 "$F" | cut -c1-16)…\` |"
  done
  echo ""
  echo "- Bundle ID: \`$APP_ID\`"
  echo "- Sürüm: $SHORT ($APP_VER)"
  echo "- App Intents metadata: $INTENTS_OK"
} >> "$GITHUB_STEP_SUMMARY"
ls -la "$OUT"
