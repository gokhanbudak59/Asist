#!/usr/bin/env bash
# Revision 4 (07 §5.12): app + widget extension.
# Asist.app -> two IPAs:
#   Asist.ipa          : ad-hoc signed — inner PlugIns/AsistWidgets.appex first, then the app, each with its
#                        entitlements (App Group group.com.gokhanbudak.asist). Sideloadly re-signs it.
#   Asist-imzasiz.ipa  : completely unsigned fallback (no entitlements; widgets then run in launcher mode,
#                        the Control Center / Lock Screen buttons still work).
# Usage: package-ipa.sh <.../Release-iphoneos/Asist.app> <output dir>
set -euo pipefail

APP_SRC="$1"
OUT="$2"
APP_NAME="$(basename "$APP_SRC")"                       # Asist.app
EXE_NAME="${APP_NAME%.app}"                             # Asist
WIDGET_REL="PlugIns/AsistWidgets.appex"
WIDGET_EXE="AsistWidgets"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_ENT="$REPO_ROOT/Generated/Asist.entitlements"
WIDGET_ENT="$REPO_ROOT/Generated/AsistWidgets.entitlements"

fail() { echo "::error::$*"; exit 1; }

# --- Pre-validation ---------------------------------------------------------
[ -d "$APP_SRC" ]                          || fail "Uygulama paketi yok: $APP_SRC"
[ -f "$APP_SRC/$EXE_NAME" ]                || fail "Çalıştırılabilir dosya yok: $APP_SRC/$EXE_NAME"
[ -f "$APP_SRC/Assets.car" ]               || fail "Derlenmiş asset kataloğu (Assets.car) yok"
[ -d "$APP_SRC/$WIDGET_REL" ]              || fail "Widget uzantısı gömülmemiş: $WIDGET_REL"
[ -f "$APP_SRC/$WIDGET_REL/$WIDGET_EXE" ]  || fail "Widget çalıştırılabiliri yok: $WIDGET_REL/$WIDGET_EXE"

PB=/usr/libexec/PlistBuddy
APP_ID=$($PB -c 'Print :CFBundleIdentifier' "$APP_SRC/Info.plist")
WID_ID=$($PB -c 'Print :CFBundleIdentifier' "$APP_SRC/$WIDGET_REL/Info.plist")
APP_VER=$($PB -c 'Print :CFBundleVersion' "$APP_SRC/Info.plist")
WID_VER=$($PB -c 'Print :CFBundleVersion' "$APP_SRC/$WIDGET_REL/Info.plist")
SHORT=$($PB -c 'Print :CFBundleShortVersionString' "$APP_SRC/Info.plist")
WID_SHORT=$($PB -c 'Print :CFBundleShortVersionString' "$APP_SRC/$WIDGET_REL/Info.plist")
EXT_POINT=$($PB -c 'Print :NSExtension:NSExtensionPointIdentifier' "$APP_SRC/$WIDGET_REL/Info.plist" 2>/dev/null || echo "")
case "$WID_ID" in "$APP_ID".*) ;; *) fail "Widget kimliği ($WID_ID) uygulama kimliğiyle ($APP_ID) önekli değil" ;; esac
[ "$APP_VER" = "$WID_VER" ]     || fail "CFBundleVersion uyuşmuyor: uygulama=$APP_VER widget=$WID_VER"
[ "$SHORT" = "$WID_SHORT" ]     || fail "CFBundleShortVersionString uyuşmuyor: uygulama=$SHORT widget=$WID_SHORT"
[ "$EXT_POINT" = "com.apple.widgetkit-extension" ] || fail "Widget NSExtensionPointIdentifier hatalı: '$EXT_POINT'"
ARCHS="$(lipo -archs "$APP_SRC/$EXE_NAME")"
[[ "$ARCHS" == *arm64* ]] || fail "arm64 dilimi yok (uygulama: $ARCHS)"
WARCHS="$(lipo -archs "$APP_SRC/$WIDGET_REL/$WIDGET_EXE")"
[[ "$WARCHS" == *arm64* ]] || fail "arm64 dilimi yok (widget: $WARCHS)"

# App Intents metadata (05a #30): reported as error annotations, packaging continues.
INTENTS_OK="evet"
check_intents() {  # $1 = bundle dir, $2 = label, $3… = intent type names
  local dir="$1" label="$2" meta name
  shift 2
  meta="$dir/Metadata.appintents/extract.actionsdata"
  if [ ! -f "$meta" ]; then
    echo "::error::App Intents metadata yok ($label): $meta"
    INTENTS_OK="hayır"
    return 0
  fi
  for name in "$@"; do
    if ! grep -q "$name" "$meta"; then
      echo "::error::App Intents metadata ($label) içinde $name yok"
      INTENTS_OK="hayır"
    fi
  done
}
check_intents "$APP_SRC" "uygulama" KaydetIntent DinleIntent BugunIntent GecikenlerIntent AsistAcIntent
check_intents "$APP_SRC/$WIDGET_REL" "widget" AsistAcIntent

# Notification sounds (D37): a missing file only falls back to the default sound.
for SND in asist-onemli.wav asist-kritik.wav; do
  if [ ! -f "$APP_SRC/$SND" ]; then
    echo "::warning::Bildirim sesi pakette yok: $SND"
  fi
done

ENT_OK="evet"
if [ ! -f "$APP_ENT" ] || [ ! -f "$WIDGET_ENT" ]; then
  echo "::warning::Entitlement dosyaları yok ($APP_ENT, $WIDGET_ENT); imza entitlement'sız atılacak"
  ENT_OK="hayır"
fi

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d)"

make_ipa() {  # $1 = staging dir (contains Payload/), $2 = ipa path
  rm -f "$2"
  (cd "$1" && zip -qry -X "$2" Payload)
  # `unzip | grep -q` under pipefail can fail with SIGPIPE (141) -> write the listing to a file first.
  unzip -Z1 "$2" > "$WORK/liste.txt"
  grep -q "^Payload/$APP_NAME/$EXE_NAME\$" "$WORK/liste.txt" || fail "IPA içinde çalıştırılabilir yok: $2"
  grep -q "^Payload/$APP_NAME/$WIDGET_REL/$WIDGET_EXE\$" "$WORK/liste.txt" || fail "IPA içinde widget yok: $2"
}

# --- 1) Fallback: completely unsigned ----------------------------------------
mkdir -p "$WORK/plain/Payload"
ditto "$APP_SRC" "$WORK/plain/Payload/$APP_NAME"
make_ipa "$WORK/plain" "$OUT/Asist-imzasiz.ipa"

# --- 2) Main: ad-hoc signature, inner bundle first, then the app --------------
mkdir -p "$WORK/signed/Payload"
ditto "$APP_SRC" "$WORK/signed/Payload/$APP_NAME"
S="$WORK/signed/Payload/$APP_NAME"
if [ "$ENT_OK" = "evet" ]; then
  codesign --force --sign - --timestamp=none --entitlements "$WIDGET_ENT" "$S/$WIDGET_REL"
  codesign --force --sign - --timestamp=none --entitlements "$APP_ENT" "$S"
else
  codesign --force --sign - --timestamp=none "$S/$WIDGET_REL"
  codesign --force --sign - --timestamp=none "$S"
fi
codesign -d --entitlements - "$S" > "$WORK/ent-app.txt" 2>&1 || true
GROUP_OK="hayır"
if grep -q "group.com.gokhanbudak.asist" "$WORK/ent-app.txt"; then GROUP_OK="evet"; fi
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
  echo "- Bundle ID: \`$APP_ID\` / widget \`$WID_ID\`"
  echo "- Sürüm: $SHORT ($APP_VER)"
  echo "- App Intents metadata: $INTENTS_OK"
  echo "- App Group entitlement (Asist.ipa): $GROUP_OK"
} >> "$GITHUB_STEP_SUMMARY"
ls -la "$OUT"
