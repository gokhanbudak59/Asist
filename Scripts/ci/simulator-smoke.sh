#!/usr/bin/env bash
# Simülatör duman testi + ekran görüntüleri (macOS runner, ci.yml `simulator` işi).
# macOS'taki /bin/bash 3.2 ile uyumludur (ilişkisel dizi, mapfile, ${x,,} yok).
#
# Kullanım: simulator-smoke.sh <Asist.app (iphonesimulator)> <çıktı klasörü>
#
# Akış: en yeni iOS çalışma zamanında iPhone simülatörü seç/oluştur → aç → durum çubuğu 09:41 → uygulamayı kur →
# AsistSeed ile gerçekçi veri üret (simülatör saatine göre) ve uygulamanın veri kabına kopyala → başlat →
# derin bağlantılarla ekranları gez, her adımda sürecin canlı olduğunu doğrula ve ekran görüntüsü al →
# kaldır/yeniden kur (tohumsuz) → tanıtım ekranı → çökme raporları + birleşik günlük.
# Uygulama çökerse (süreç kaybolursa veya çökme raporu oluşursa) ya da bir adım yapılamazsa çıkış kodu 1'dir.
#
# Çıktı klasörü (sim-gunlukleri artefaktı):
#   NN-*.png            küçültülmüş ekran görüntüleri (en uzun kenar 1400 px) — ci-logs dalına yayınlanır
#   tam/NN-*.png        tam çözünürlüklü ekran görüntüleri
#   ozet.txt, adimlar.txt, ekranlar.txt, smoke.log, seed.log, app-unified.log, app-hatalar.log, app-stderr-N.log
#   crash/              bu çalışmada oluşan Asist çökme raporları (.ips)
#   seed/               asist-data.json (uygulamanın okuduğu), asist-data-okunur.json, seed-ids.txt
#   ham/                ham listeler, tam günlükler, stdout
#   derleme/            (ci.yml yazar) xcodegen / xcodebuild günlükleri
set -euo pipefail

APP_PATH="${1:?Asist.app yolu}"
OUT="${2:?çıktı klasörü}"
BUNDLE_ID="${ASIST_BUNDLE_ID:-com.gokhanbudak.asist}"
LOG_SUBSYSTEM="com.gokhanbudak.asist"              # App/Support/AsistLog.swift
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PKG_DIR="$REPO_ROOT/Packages/AsistCore"

mkdir -p "$OUT" "$OUT/tam" "$OUT/crash" "$OUT/seed" "$OUT/ham"
LOG="$OUT/smoke.log"
SUMMARY="$OUT/ozet.txt"
STEPS="$OUT/adimlar.txt"
SCREENS="$OUT/ekranlar.txt"
MARKER="$OUT/ham/baslangic.marker"
: > "$LOG"
: > "$SUMMARY"
: > "$STEPS"
: > "$SCREENS"
touch "$MARKER"

UDID=""
DEVICE_NAME=""
RUNTIME_NAME=""
SIM_DATA_DIR=""
SEED_BIN=""
DETAIL_ID=""
APP_PID=""
LAUNCH_NO=0
SHOTS=0
CRASHED=0
CRASH_REPORTS=0
FAILED=0
FINISHED=0

# MARK: - Yardımcılar

log() {
  local line
  line="[$(date -u +%H:%M:%S)] $*"
  echo "$line"
  echo "$line" >> "$LOG"
}

note() {
  echo "$*" >> "$SUMMARY"
  log "$*"
}

host_tz() {
  local link
  link=$(readlink /etc/localtime 2>/dev/null) || link=""
  printf '%s\n' "${link##*zoneinfo/}"
}

# run_with_timeout <saniye> <komut...> — macOS'ta `timeout` yok. Süre dolarsa 124 döner.
run_with_timeout() {
  local secs="$1"
  shift
  "$@" &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$secs" ]; then
      kill "$pid" 2>/dev/null || true
      sleep 2
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
}

# MARK: - Simülatör seçimi

write_picker() {
cat > "$OUT/ham/pick_device.py" <<'PY'
# simctl list -j çıktısından en yeni iOS çalışma zamanını ve tercih edilen iPhone'u seçer.
# Çıktı (sekmeyle ayrılmış tek satır):
#   USE     <udid> <cihaz adı> <çalışma zamanı adı>
#   CREATE  <cihaz türü kimliği> <çalışma zamanı kimliği> <cihaz adı> <çalışma zamanı adı> <yedek udid>
#   NONE
import json
import re
import sys


def version_key(text):
    return tuple(int(part) for part in re.findall(r"\d+", text or ""))


def score(name):
    name = name or ""
    if name == "iPhone 14 Pro Max":  # kullanıcının cihazı
        return (4, 14)
    match = re.match(r"^iPhone (\d+) Pro Max$", name)
    if match:
        return (3, int(match.group(1)))
    if name.startswith("iPhone") and "Pro Max" in name:
        return (2, 0)
    match = re.match(r"^iPhone (\d+)", name)
    if match:
        return (1, int(match.group(1)))
    if name.startswith("iPhone"):
        return (1, 0)
    return (0, 0)


def main():
    with open(sys.argv[1]) as handle:
        data = json.load(handle)
    runtimes = []
    for runtime in data.get("runtimes", []):
        identifier = runtime.get("identifier", "")
        is_ios = runtime.get("platform") == "iOS" or ".SimRuntime.iOS-" in identifier
        available = runtime.get("isAvailable") is True or runtime.get("availability") == "(available)"
        if is_ios and available:
            runtimes.append(runtime)
    if not runtimes:
        print("NONE")
        return
    runtimes.sort(key=lambda item: version_key(item.get("version", "")), reverse=True)
    runtime = runtimes[0]
    runtime_id = runtime.get("identifier", "")
    runtime_name = runtime.get("name", runtime_id)

    best_device = None
    for device in data.get("devices", {}).get(runtime_id, []):
        if device.get("isAvailable") is False:
            continue
        value = score(device.get("name"))
        if value[0] == 0:
            continue
        if best_device is None or value > best_device[0]:
            best_device = (value, device)

    best_type = None
    for device_type in runtime.get("supportedDeviceTypes") or data.get("devicetypes", []):
        value = score(device_type.get("name"))
        if value[0] == 0:
            continue
        if best_type is None or value > best_type[0]:
            best_type = (value, device_type)

    if best_device is not None and (best_type is None or best_device[0] >= best_type[0]):
        device = best_device[1]
        print("\t".join(["USE", device.get("udid", ""), device.get("name", ""), runtime_name]))
    elif best_type is not None:
        device_type = best_type[1]
        fallback = best_device[1].get("udid", "") if best_device is not None else ""
        print("\t".join(["CREATE", device_type.get("identifier", ""), runtime_id, device_type.get("name", ""),
                         runtime_name, fallback]))
    else:
        print("NONE")


main()
PY
}

# Python yoksa: metin listesinden son (en yeni çalışma zamanı) "iPhone … Pro Max" cihazının UDID'si.
fallback_udid() {
  xcrun simctl list devices available 2>/dev/null \
    | grep -E '^[[:space:]]+iPhone .*Pro Max \([0-9A-Fa-f-]{36}\)' \
    | tail -n 1 \
    | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/' || true
}

pick_device() {
  local json="$OUT/ham/simctl-list.json" decision="" kind type_id runtime_id fallback
  if ! xcrun simctl list -j devices devicetypes runtimes > "$json" 2>>"$LOG"; then
    log "UYARI: simctl list -j başarısız"
  fi
  xcrun simctl list runtimes > "$OUT/ham/simctl-runtimes.txt" 2>&1 || true
  write_picker
  if command -v python3 >/dev/null 2>&1; then
    decision=$(python3 "$OUT/ham/pick_device.py" "$json" 2>>"$LOG") || decision=""
  fi
  log "Seçim: ${decision:-yok}"
  kind=$(printf '%s\n' "$decision" | cut -f1)
  case "$kind" in
    USE)
      UDID=$(printf '%s\n' "$decision" | cut -f2)
      DEVICE_NAME=$(printf '%s\n' "$decision" | cut -f3)
      RUNTIME_NAME=$(printf '%s\n' "$decision" | cut -f4)
      ;;
    CREATE)
      type_id=$(printf '%s\n' "$decision" | cut -f2)
      runtime_id=$(printf '%s\n' "$decision" | cut -f3)
      DEVICE_NAME=$(printf '%s\n' "$decision" | cut -f4)
      RUNTIME_NAME=$(printf '%s\n' "$decision" | cut -f5)
      fallback=$(printf '%s\n' "$decision" | cut -f6)
      if UDID=$(xcrun simctl create "Asist Duman" "$type_id" "$runtime_id" 2>>"$LOG"); then
        log "Simülatör oluşturuldu: $DEVICE_NAME ($UDID)"
      else
        log "UYARI: $DEVICE_NAME oluşturulamadı; mevcut cihaz kullanılacak"
        UDID="$fallback"
        DEVICE_NAME="(mevcut cihaz)"
      fi
      ;;
  esac
  if [ -z "$UDID" ]; then
    UDID=$(fallback_udid)
    DEVICE_NAME="(metin listesinden seçildi)"
  fi
  if [ -z "$UDID" ]; then
    note "HATA: kullanılabilir iOS simülatörü bulunamadı (ham/simctl-runtimes.txt)"
    return 1
  fi
  SIM_DATA_DIR="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data"
  return 0
}

status_bar() {
  xcrun simctl status_bar "$UDID" override --time "09:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
      --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 >>"$LOG" 2>&1 \
    || xcrun simctl status_bar "$UDID" override --time "09:41" >>"$LOG" 2>&1 \
    || log "UYARI: durum çubuğu ayarlanamadı"
}

# MARK: - Tohum verisi

build_seed() {
  local bin_dir
  log "AsistSeed derleniyor (swift build)…"
  if ! (cd "$PKG_DIR" && swift build -c debug --product AsistSeed) > "$OUT/seed/seed-build.log" 2>&1; then
    note "HATA: AsistSeed derlenemedi (seed/seed-build.log)"
    tail -n 40 "$OUT/seed/seed-build.log" >> "$LOG" || true
    return 1
  fi
  bin_dir=$(cd "$PKG_DIR" && swift build -c debug --product AsistSeed --show-bin-path 2>>"$LOG") || bin_dir=""
  SEED_BIN="$bin_dir/AsistSeed"
  if [ -z "$bin_dir" ] || [ ! -x "$SEED_BIN" ]; then
    note "HATA: AsistSeed ikilisi bulunamadı: $SEED_BIN"
    return 1
  fi
  log "AsistSeed hazır: $SEED_BIN"
}

run_seed() {
  local now
  # Simülatörün saati Mac'in saatidir; saat dilimi de Mac'inkidir (AsistSeed varsayılanı TimeZone.current).
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  log "AsistSeed çalışıyor: --now $now (Mac saat dilimi: $(host_tz))"
  if ! "$SEED_BIN" --now "$now" --out "$OUT/seed/asist-data.json" \
      --pretty-copy "$OUT/seed/asist-data-okunur.json" --ids "$OUT/seed/seed-ids.txt" > "$OUT/seed.log" 2>&1; then
    note "HATA: AsistSeed başarısız (seed.log)"
    tail -n 40 "$OUT/seed.log" >> "$LOG" || true
    return 1
  fi
  DETAIL_ID=$(sed -n 's/^DETAY_ID=//p' "$OUT/seed/seed-ids.txt" | head -n 1) || DETAIL_ID=""
  note "Tohum: $(grep -c '^\[' "$OUT/seed.log" || true) satır, ayrıntı kaydı: ${DETAIL_ID:-yok}"
  grep -E '^Bugün ekranı:' "$OUT/seed.log" >> "$SUMMARY" || true
}

# Uygulama kurulduktan sonra, ilk açılıştan ÖNCE: <veri kabı>/Library/Application Support/Asist/asist-data.json
copy_seed() {
  local container="" target
  container=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>>"$LOG") || container=""
  if [ -z "$container" ]; then
    log "Veri kabı henüz yok; uygulama bir kez açılıp kapatılıyor"
    launch_app "veri kabı oluşturma" || true
    sleep 6
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" >>"$LOG" 2>&1 || true
    sleep 2
    container=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>>"$LOG") || container=""
  fi
  if [ -z "$container" ] || [ ! -d "$container" ]; then
    note "HATA: uygulamanın veri kabı bulunamadı"
    return 1
  fi
  target="$container/Library/Application Support/Asist"
  # Bu işlev `if` içinde çağrılır (errexit kapalı): her hata açıkça denetlenir.
  if ! mkdir -p "$target"; then
    note "HATA: veri klasörü oluşturulamadı: $target"
    return 1
  fi
  rm -f "$target/asist-data.prev.json" || true
  if ! cp "$OUT/seed/asist-data.json" "$target/asist-data.json"; then
    note "HATA: tohum verisi veri kabına kopyalanamadı"
    return 1
  fi
  printf '%s\n' "$container" > "$OUT/ham/veri-kabi.txt" || true
  log "Tohum verisi kopyalandı: $target/asist-data.json"
}

# MARK: - Uygulama

install_app() {
  xcrun simctl install "$UDID" "$APP_PATH" >>"$LOG" 2>&1
}

grant_privacy() {
  xcrun simctl privacy "$UDID" grant microphone "$BUNDLE_ID" >>"$LOG" 2>&1 \
    || log "UYARI: mikrofon izni verilemedi (önemsiz)"
}

launch_app() {
  local why="$1" output=""
  LAUNCH_NO=$((LAUNCH_NO + 1))
  if ! output=$(xcrun simctl launch --terminate-running-process \
      --stdout="$OUT/ham/app-stdout-$LAUNCH_NO.log" --stderr="$OUT/app-stderr-$LAUNCH_NO.log" \
      "$UDID" "$BUNDLE_ID" 2>&1); then
    note "HATA: uygulama başlatılamadı ($why): $output"
    APP_PID=""
    return 1
  fi
  APP_PID=$(printf '%s\n' "$output" | sed -n 's/^.*: *\([0-9][0-9]*\)[[:space:]]*$/\1/p' | tail -n 1) || APP_PID=""
  log "Uygulama başlatıldı ($why), pid=${APP_PID:-?}"
}

# Uygulama süreci canlı mı? Önce simülatörün launchd listesi (PID sütunu sayı olmalı), sonra Mac'teki süreç
# (simülatördeki uygulama Mac üzerinde gerçek bir süreçtir; `simctl launch` o PID'i yazar).
app_alive() {
  local line="" pid=""
  line=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep "UIKitApplication:$BUNDLE_ID" | head -n 1) \
    || line=""
  if [ -n "$line" ]; then
    pid=$(printf '%s\n' "$line" | awk '{print $1}')
    case "$pid" in
      ''|*[!0-9]*) ;;
      *) return 0 ;;
    esac
  fi
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    return 0
  fi
  return 1
}

check_alive() {
  local step="$1"
  if app_alive; then
    echo "OK     $step" >> "$STEPS"
    return 0
  fi
  CRASHED=1
  echo "COKME  $step" >> "$STEPS"
  note "HATA: '$step' adımında uygulama süreci yok (çökme)"
  return 1
}

shot() {
  local name="$1" what="$2"
  local full="$OUT/tam/$name.png"
  if ! xcrun simctl io "$UDID" screenshot --type=png "$full" >>"$LOG" 2>&1; then
    log "UYARI: ekran görüntüsü alınamadı: $name"
    return 0
  fi
  if ! sips -Z 1400 "$full" --out "$OUT/$name.png" >/dev/null 2>&1; then
    cp "$full" "$OUT/$name.png"
  fi
  SHOTS=$((SHOTS + 1))
  echo "$name.png — $what" >> "$SCREENS"
  log "Ekran görüntüsü: $name.png ($what)"
}

# Canlılık kontrolü + ekran görüntüsü; süreç yoksa kanıt görüntüsü alır ve devam etmek için yeniden başlatır.
capture() {
  local name="$1" what="$2"
  if check_alive "$name"; then
    shot "$name" "$what"
  else
    shot "$name-COKME" "$what (uygulama çalışmıyor)"
    launch_app "çökme sonrası ($name)" || true
    sleep 8
  fi
}

visit() {
  local url="$1" name="$2" what="$3" wait_s="${4:-4}"
  log "Bağlantı: $url"
  if ! xcrun simctl openurl "$UDID" "$url" >>"$LOG" 2>&1; then
    note "UYARI: openurl başarısız: $url"
  fi
  sleep "$wait_s"
  capture "$name" "$what"
}

# MARK: - Günlükler ve çökme raporları

collect_logs() {
  [ -n "$UDID" ] || return 0
  xcrun simctl spawn "$UDID" log show --last 45m --style compact --info --debug \
      --predicate "subsystem BEGINSWITH \"$LOG_SUBSYSTEM\"" > "$OUT/ham/app-unified-tam.log" 2>&1 || true
  tail -n 4000 "$OUT/ham/app-unified-tam.log" > "$OUT/app-unified.log" 2>/dev/null || true
  xcrun simctl spawn "$UDID" log show --last 45m --style compact \
      --predicate 'process == "Asist" AND (messageType == error OR messageType == fault)' \
      > "$OUT/ham/app-hatalar-tam.log" 2>&1 || true
  tail -n 1500 "$OUT/ham/app-hatalar-tam.log" > "$OUT/app-hatalar.log" 2>/dev/null || true
}

collect_crashes() {
  local dir f base count=0
  for dir in "$HOME/Library/Logs/DiagnosticReports" "$HOME/Library/Logs/DiagnosticReports/Retired" \
             "${SIM_DATA_DIR:-/nonexistent}/Library/Logs/CrashReporter"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*; do
      [ -f "$f" ] || continue
      base=$(basename "$f")
      case "$base" in
        *Asist*|*asist*) ;;
        *) continue ;;
      esac
      [ "$f" -nt "$MARKER" ] || continue
      if cp "$f" "$OUT/crash/$base"; then
        count=$((count + 1))
      fi
    done
  done
  CRASH_REPORTS=$count
  if [ "$count" -gt 0 ]; then
    CRASHED=1
    note "HATA: bu çalışmada $count Asist çökme raporu oluştu (crash/)"
    for f in "$OUT"/crash/*; do
      [ -f "$f" ] || continue
      { echo "===== $(basename "$f")"; head -n 80 "$f"; } >> "$OUT/cokme-ozeti.txt"
    done
  fi
}

finish() {
  local rc=$?
  local result
  set +e
  trap - EXIT
  if [ -n "$UDID" ]; then
    sleep 5                                          # ReportCrash raporu yazsın
    collect_logs
  fi
  collect_crashes
  find "$OUT" -maxdepth 1 -name 'app-std*.log' -size 0 -delete 2>/dev/null
  if [ "$CRASHED" = "1" ]; then
    result="ÇÖKTÜ"
  elif [ "$rc" != "0" ] || [ "$FAILED" = "1" ] || [ "$FINISHED" != "1" ] || [ "$SHOTS" -eq 0 ]; then
    result="BAŞARISIZ"
  else
    result="BAŞARILI"
  fi
  note "Sonuç: $result (ekran görüntüsü: $SHOTS, çökme raporu: $CRASH_REPORTS, betik kodu: $rc)"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "### Simülatör duman testi: $result"
      echo '```'
      cat "$SUMMARY"
      echo "--- adımlar"
      cat "$STEPS"
      echo "--- ekranlar"
      cat "$SCREENS"
      echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  if [ "$result" != "BAŞARILI" ]; then
    if [ "$CRASHED" = "1" ]; then
      echo "::error::Asist simülatörde çöktü veya süreç kayboldu (sim-gunlukleri: crash/, app-hatalar.log, adimlar.txt)"
    else
      echo "::error::Simülatör duman testi tamamlanamadı (sim-gunlukleri: smoke.log, ozet.txt)"
    fi
    exit 1
  fi
  exit 0
}
trap finish EXIT

# MARK: - Akış

main() {
  local seed_ok=1
  log "Başlangıç: $(date -u '+%Y-%m-%d %H:%M:%S') UTC, Mac saat dilimi: $(host_tz)"
  if [ ! -d "$APP_PATH" ]; then
    note "HATA: uygulama paketi yok: $APP_PATH"
    FAILED=1
    return 1
  fi
  if ! pick_device; then
    FAILED=1
    return 1
  fi
  note "Simülatör: $DEVICE_NAME — $RUNTIME_NAME (udid $UDID)"
  xcrun simctl boot "$UDID" >>"$LOG" 2>&1 || true   # zaten açıksa hata verir; açılış arka planda sürer

  # Simülatör açılırken tohum aracını derle.
  if ! build_seed; then
    seed_ok=0
    FAILED=1
  fi

  if ! run_with_timeout 900 xcrun simctl bootstatus "$UDID" -b >>"$LOG" 2>&1; then
    note "HATA: simülatör açılamadı (bootstatus)"
    FAILED=1
    return 1
  fi
  log "Simülatör açıldı"
  xcrun simctl ui "$UDID" appearance light >>"$LOG" 2>&1 || true
  status_bar

  if ! install_app; then
    note "HATA: uygulama kurulamadı"
    FAILED=1
    return 1
  fi
  grant_privacy
  if [ "$seed_ok" = "1" ]; then
    if run_seed && copy_seed; then
      note "Tohum verisi yüklendi"
    else
      seed_ok=0
      FAILED=1
    fi
  fi
  if [ "$seed_ok" != "1" ]; then
    note "UYARI: tohum verisi YOK — ekranlar tanıtım/boş durum gösterecek"
  fi

  # 1) Tohumlu oturum
  if ! launch_app "tohumlu ilk açılış"; then
    FAILED=1
  fi
  sleep 20                                           # yeni açılmış simülatörde ilk açılış yavaş olabilir
  capture "01-bugun" "Bugün (açık tema)"
  xcrun simctl ui "$UDID" appearance dark >>"$LOG" 2>&1 || log "UYARI: karanlık tema ayarlanamadı"
  sleep 3
  capture "02-bugun-karanlik" "Bugün (karanlık tema)"
  xcrun simctl ui "$UDID" appearance light >>"$LOG" 2>&1 || true
  status_bar
  sleep 2
  visit "asist://sekme/listeler" "03-listeler" "Listeler sekmesi (asist://sekme/listeler)"
  visit "asist://sekme/projeler" "04-projeler" "Projeler sekmesi (asist://sekme/projeler)"
  visit "asist://sekme/ayarlar" "05-ayarlar" "Ayarlar sekmesi (asist://sekme/ayarlar)"
  # Akıllı Mod ekranı v1.0'da yok (Ek B, v1.1); ulaşılabilen ayar alt ekranı Tetikleyiciler.
  visit "asist://ayarlar/tetikleyiciler" "06-ayarlar-tetikleyiciler" "Ayarlar › Tetikleyiciler"
  if [ -n "$DETAIL_ID" ]; then
    visit "asist://kayit/$DETAIL_ID" "07-kayit-detay" "Kayıt ayrıntısı (asist://kayit/$DETAIL_ID)"
  else
    note "UYARI: tohumdan kayıt kimliği gelmedi; ayrıntı ekranı atlandı"
  fi
  visit "asist://gunsonu" "08-gun-sonu" "Gün sonu (asist://gunsonu)"
  visit "asist://yaz" "09-yaz" "Yaz sayfası (asist://yaz)" 5
  visit "asist://sekme/bugun" "10-bugun-sekme" "asist://sekme/bugun (sayfa kapanır, Bugün kökü)"

  # 2) Temiz kurulum (tohumsuz): tanıtım ekranı
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >>"$LOG" 2>&1 || true
  sleep 2
  xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >>"$LOG" 2>&1 || log "UYARI: kaldırma başarısız"
  if ! install_app; then
    note "HATA: yeniden kurulum başarısız"
    FAILED=1
    return 1
  fi
  grant_privacy
  if ! launch_app "temiz kurulum (tohumsuz)"; then
    FAILED=1
  fi
  sleep 15
  capture "11-tanitim" "Temiz kurulum: tanıtım ekranı"
  FINISHED=1
  return 0
}

main
