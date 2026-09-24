#!/usr/bin/env bash
#
# VICIdial Cluster - Dialer / Telephony (Asterisk) node crontab.
# Replaces the current crontab with a node-local schedule only (no cluster-wide
# DB maintenance jobs) and keeps a timestamped backup in /root.
# Run this on EVERY dialer node in the cluster.
#
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[!] This script must be run as root (try: sudo bash $0)" >&2
    exit 1
fi

# 1. Create a timestamped backup of the current crontab
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

# 2. Build the new optimized crontab in a temp file, then install it
TMP_CRON="$(mktemp)"
trap 'rm -f "$TMP_CRON"' EXIT

cat >"$TMP_CRON" <<'EOF'
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

### Audio Sync hourly
* 1 * * * /usr/share/astguiclient/ADMIN_audio_store_sync.pl --upload --quiet

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

### Remove local old recordings & logs
24 1 * * * /usr/bin/find /var/spool/asterisk/monitorDONE/ORIG -maxdepth 2 -type f -mtime +1 -print | xargs -r rm -f
28 0 * * * /usr/bin/find /var/log/astguiclient -maxdepth 1 -type f -mtime +2 -print | xargs -r rm -f
29 0 * * * /usr/bin/find /var/log/asterisk -maxdepth 3 -type f -mtime +2 -print | xargs -r rm -f

### Dynamic Firewall
@reboot /usr/bin/VB-firewall --whitelist=ViciWhite --dynamic --quiet
* * * * * /usr/bin/VB-firewall --whitelist=ViciWhite --dynamic --quiet
* * * * * sleep 10; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 20; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 30; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 40; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 50; /usr/bin/VB-firewall --white --dynamic --quiet
EOF

if ! crontab "$TMP_CRON"; then
    echo "[!] Failed to install the new crontab - the previous crontab is unchanged." >&2
    exit 1
fi

echo "[+] Dialer server crontab successfully updated."
if [ -n "$BACKUP_FILE" ]; then
    echo "[i] Roll back with: crontab $BACKUP_FILE"
fi
