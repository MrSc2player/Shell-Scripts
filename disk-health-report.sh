#!/usr/bin/env bash
set -u -o pipefail

HOST="$(hostname -s)"
GOTIFY_URL=""       # Hier deine Gotify URL einfügen
GOTIFY_TOKEN=""     # Hier dein Gotify Token einfügen

send_disk_report() {
  local dev="$1" model="$2" sn="$3" health="$4" temp="$5" realloc="$6" pending="$7" hours="$8"

  local title="💾 $dev $health"
  local message="Host: $HOST
Modell: ${model:-Unbekannt}
SN: ${sn:-Unbekannt}
Status: $health"

  [[ -n "${temp:-}" && "$temp" != "-" ]] && message+="
Temp: $temp°C"
  [[ -n "${realloc:-}" && "$realloc" != "-" ]] && message+="
Reallocated: $realloc"
  [[ -n "${pending:-}" && "$pending" != "-" ]] && message+="
Pending: $pending"
  [[ -n "${hours:-}" && "$hours" != "-" ]] && message+="
Stunden: $hours"

  local prio=3
  if [[ "$health" == "FEHLER" ]]; then
    prio=9
  elif [[ "$health" == "WARNUNG" ]]; then
    prio=6
  elif [[ "$health" == "SMART-N/A" ]]; then
    prio=4
  fi

  curl -sS -X POST "$GOTIFY_URL/message?token=$GOTIFY_TOKEN" \
    -F "title=$title" \
    -F "message=$message" \
    -F "priority=$prio" >/dev/null
}

check_usb_drive() {
  local dev="$1"
  local disk="${dev#/dev/}"

  local mounted="Nein"
  local mount_path="Nicht gemountet"
  if mount | grep -q "^$dev"; then
    mounted="Ja"
    mount_path="$(mount | awk -v d="$dev" '$1 ~ "^"d {print $3; exit}')"
  fi

  local io_errors
  io_errors="$(dmesg | tail -200 | grep -i "$disk.*\(error\|i/o\|timeout\|fail\|reset\)" | wc -l || true)"

  local usb_count
  usb_count="$(lsusb 2>/dev/null | grep -i "storage\|mass\|disk\|JMicron\|ASMedia\|Realtek\|Seagate\|WD\|Toshiba" | wc -l || true)"

  local title="🔌 USB $disk OK"
  local message="Mount: $mounted ($mount_path)
I/O-Fehler: $io_errors
USB-Geräte: $usb_count"

  local prio=3
  if [[ "${io_errors:-0}" -gt 0 ]]; then
    title="🚨 USB $disk IO-FEHLER"
    prio=8
  fi

  curl -sS -X POST "$GOTIFY_URL/message?token=$GOTIFY_TOKEN" \
    -F "title=$title" \
    -F "message=$message" \
    -F "priority=$prio" >/dev/null
}

if command -v zpool >/dev/null 2>&1; then
  zfs_status="$(zpool status -x 2>/dev/null || echo 'ZFS nicht verfügbar')"
  if echo "$zfs_status" | grep -qE "(DEGRADED|FAULTED|OFFLINE|errors:|unavail|scrub.*errors)"; then
    curl -sS -X POST "$GOTIFY_URL/message?token=$GOTIFY_TOKEN" \
      -F "title=🚨 ZFS KRITISCH $HOST" \
      -F "message=$zfs_status" \
      -F "priority=9" >/dev/null
  fi
fi

mapfile -t DISKS < <(lsblk -dn -o NAME,TYPE | awk '
  $2=="disk" &&
  $1 ~ /^sd/ &&
  $1 !~ /^zd/ &&
  $1 !~ /^loop/ &&
  $1 !~ /^ram/ &&
  $1 !~ /^sr/ {print "/dev/"$1}
')

for d in "${DISKS[@]}"; do
  if [[ "$d" == "/dev/sdc" ]]; then
    check_usb_drive "$d"
    continue
  fi

  info="$(smartctl -a "$d" 2>&1 || true)"

  model="$(echo "$info" | grep -m1 'Device Model:\|Model Family:' | sed 's/.*: *//' | xargs || true)"
  sn="$(echo "$info" | grep -m1 'Serial Number:' | sed 's/.*: *//' | xargs || true)"

  health="SMART-N/A"
  if echo "$info" | grep -q 'SMART overall-health self-assessment test result: PASSED'; then
    health="OK"
  elif echo "$info" | grep -q 'SMART overall-health self-assessment test result: FAILED'; then
    health="FEHLER"
  elif [[ -n "$info" ]]; then
    health="WARNUNG"
  fi

  temp="$(echo "$info" | awk '/Temperature_Celsius/ {print $10; exit}' || echo "-")"
  realloc="$(echo "$info" | awk '/Reallocated_Sector_Ct/ {print $10; exit}' || echo "-")"
  pending="$(echo "$info" | awk '/Current_Pending_Sector/ {print $10; exit}' || echo "-")"
  hours="$(echo "$info" | awk '/Power_On_Hours/ {print $10; exit}' || echo "-")"

  send_disk_report "$d" "$model" "$sn" "$health" "$temp" "$realloc" "$pending" "$hours"
done

echo "Alle Berichte gesendet!"
