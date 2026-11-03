#!/bin/bash

# Konfiguration
GOTIFY_URL=""           # Hier deine Gotify URL einfügen
GOTIFY_TOKEN=""         # HIer dein Gotify Token einfügen
HOSTNAME=$(hostname)
PRIORITY=5

send_gotify() {
    curl -s -X POST "$GOTIFY_URL/message?token=$GOTIFY_TOKEN" \
        -F "title=$1" \
        -F "message=$2" \
        -F "priority=$PRIORITY" > /dev/null
}

LOGFILE="/var/log/proxmox-apt-notify.log"
echo "$(date): Proxmox APT-Check gestartet" >> "$LOGFILE"

if apt-get update >> "$LOGFILE" 2>&1; then
    UPDATE_COUNT=$(apt list --upgradable 2>/dev/null | grep -v "^Listing" | wc -l)
    
    if [ "$UPDATE_COUNT" -gt 0 ]; then
        UPDATES_LIST=$(apt list --upgradable 2>/dev/null | grep -v "^Listing" | head -10)
        send_gotify "🚨 PROXMOX UPDATES $HOSTNAME" "$UPDATE_COUNT Updates gefunden:\n$UPDATES_LIST\nLog: $LOGFILE"
        echo "$(date): $UPDATE_COUNT Updates -> Gotify gesendet" >> "$LOGFILE"
    else
        send_gotify "✅ Proxmox $HOSTNAME: Aktuell" "Keine Updates verfügbar."
        echo "$(date): Keine Updates" >> "$LOGFILE"
    fi
else
    send_gotify "❌ PROXMOX FEHLER $HOSTNAME" "apt-get update fehlgeschlagen!\nLog: $LOGFILE"
    echo "$(date): apt update FEHLER" >> "$LOGFILE"
fi
