#!/usr/bin/env bash
#
# VICIdial Cluster - Interactive Dialer Node Crontab Installer
# Prompts directly for the off-peak start hour in UTC format (e.g., 6 for 11 PM MST)
# and applies a lightweight, local-only crontab.
#
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[!] This script must be run as root (try: sudo bash $0)" >&2
    exit 1
fi

echo "=================================================="
echo "      VICIdial Dialer Node Crontab Setup          "
echo "=================================================="

# 1. Prompt directly for UTC Off-Peak start hour
while true; do
    read -p "[?] Enter off-peak start hour in UTC (0-23, e.g. 6 for 06:00 UTC / 11 PM MST): " UTC_OFFPEAK_HOUR
    if [[ "$UTC_OFFPEAK_HOUR" =~ ^[0-9]+$ ]] && [ "$UTC_OFFPEAK_HOUR" -ge 0 ] && [ "$UTC_OFFPEAK_HOUR" -le 23 ]; then
        break
    fi
    echo "[!] Invalid input. Please enter a number between 0 and 23."
done

# Format integer safely
CRON_HOUR=$((10#$UTC_OFFPEAK_HOUR))
SYNC_HOUR=$(( (CRON_HOUR + 1) % 24 ))

echo ""
echo "[+] Selected UTC Off-Peak Start: ${CRON_HOUR}:00 UTC"
echo ""

# 2. Create a timestamped backup of current crontab
BACKUP_DIR="${BACKUP_DIR:-/root}"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/crontab_backup_dialer_$(date +%Y%m%d_%H%M%S).txt"

if crontab -l >"$BACKUP_FILE" 2>/dev/null && [ -s "$BACKUP_FILE" ]; then
    echo "[+] Existing crontab backed up to: $BACKUP_FILE"
else
    rm -f "$BACKUP_FILE"
    BACKUP_FILE=""
    echo "[!] No existing crontab found - nothing to back up."
fi

# 3. Build the new optimized crontab in a temp file
TMP_CRON="$(mktemp)"
trap 'rm -f "$TMP_CRON"' EXIT

cat >"$TMP_CRON" <<CRON_EOF
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

### Audio Sync (Runs 1 hour after off-peak start)
* ${SYNC_HOUR} * * * /usr/share/astguiclient/ADMIN_audio_store_sync.pl --upload --quiet

### Recording mixing/compressing scripts (Local to this dialer)
0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57 * * * * /usr/share/astguiclient/AST_CRON_audio_1_move_mix.pl --MIX
0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57 * * * * /usr/share/astguiclient/AST_CRON_audio_1_move_VDonly.pl
1,4,7,10,13,16,19,22,25,28,31,34,37,40,43,46,49,52,55,58 * * * * /usr/share/astguiclient/AST_CRON_audio_2_compress.pl --MP3 --HTTPS

### Keepalive script for astguiclient processes
* * * * * /usr/share/astguiclient/ADMIN_keepalive_ALL.pl

### Kill Hangup script for Asterisk updaters
* * * * * /usr/share/astguiclient/AST_manager_kill_hung_congested.pl

### Updater for voicemail
* * * * * /usr/share/astguiclient/AST_vm_update.pl

### Flush queue DB table every hour for entries older than 1 hour
11 * * * * /usr/share/astguiclient/AST_flush_DBqueue.pl -q

### Remove local old recordings & logs (Scheduled during off-peak window)
24 ${CRON_HOUR} * * * /usr/bin/find /var/spool/asterisk/monitorDONE/ORIG -maxdepth 2 -type f -mtime +1 -print | xargs -r rm -f
28 ${CRON_HOUR} * * * /usr/bin/find /var/log/astguiclient -maxdepth 1 -type f -mtime +2 -print | xargs -r rm -f
29 ${CRON_HOUR} * * * /usr/bin/find /var/log/asterisk -maxdepth 3 -type f -mtime +2 -print | xargs -r rm -f

### Dynamic Firewall
@reboot /usr/bin/VB-firewall --whitelist=ViciWhite --dynamic --quiet
* * * * * /usr/bin/VB-firewall --whitelist=ViciWhite --dynamic --quiet
* * * * * sleep 10; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 20; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 30; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 40; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 50; /usr/bin/VB-firewall --white --dynamic --quiet
CRON_EOF

if ! crontab "$TMP_CRON"; then
    echo "[!] Failed to install the new crontab - previous crontab unchanged." >&2
    exit 1
fi

echo "[+] Dialer server crontab successfully updated!"
if [ -n "$BACKUP_FILE" ]; then
    echo "[i] Roll back with: crontab $BACKUP_FILE"
fi
