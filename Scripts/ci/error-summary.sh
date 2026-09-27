#!/usr/bin/env bash
# xcodebuild günlüğünden derleyici hatalarını çıkarıp iş özetine (Summary) yazar.
# Kullanım: error-summary.sh <xcodebuild.log>
set -uo pipefail
LOG="${1:?log yolu}"
[ -f "$LOG" ] || { echo "Günlük yok: $LOG"; exit 0; }

{
  echo "## Derleme hataları"
  echo '```'
  # Swift/Clang tanıları: /yol/Dosya.swift:12:5: error: ...
  grep -E ":[0-9]+:[0-9]+: (fatal )?error:" "$LOG" | sed -E "s#^.*/(App|Widgets|Shared|Packages)/#\1/#" | sort -u | head -60
  # Konumsuz hatalar (imza, plist, bağlama, eksik dosya)
  grep -E "^(error|fatal error|ld: error|clang: error): " "$LOG" | sort -u | head -20
  echo '```'
  echo "### Başarısız komutlar"
  echo '```'
  grep -A 25 "The following build commands failed:" "$LOG" | head -30
  echo '```'
} >> "$GITHUB_STEP_SUMMARY"

grep -cE ":[0-9]+:[0-9]+: (fatal )?error:" "$LOG" | xargs -I{} echo "Toplam derleyici hatası satırı: {}"
exit 0
