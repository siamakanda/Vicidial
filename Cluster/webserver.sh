#!/usr/bin/env bash
#
# VICIdial Cluster - Main / Web / DB Server Setup Script
# Replaces current crontab with an off-peak optimized schedule
# (11:00 PM - 7:00 AM MST / 06:00 - 14:00 UTC), creates a timestamped backup,
# and configures MariaDB binary logging.
#
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[!] This script must be run as root (try: sudo bash $0)" >&2
    exit 1
fi

echo "=================================================="
echo "    VICIdial Main/DB Server Deployment Script     "
echo "=================================================="

# 1. Create a timestamped backup of the current crontab
BACKUP_DIR="${BACKUP_DIR:-/root}"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/crontab_backup_main_$(date +%Y%m%d_%H%M%S).txt"

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

### Recording mixing/compressing
0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57 * * * * /usr/share/astguiclient/AST_CRON_audio_1_move_mix.pl --MIX
0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57 * * * * /usr/share/astguiclient/AST_CRON_audio_1_move_VDonly.pl
1,4,7,10,13,16,19,22,25,28,31,34,37,40,43,46,49,52,55,58 * * * * /usr/share/astguiclient/AST_CRON_audio_2_compress.pl --MP3 --HTTPS

### Keepalive script for astguiclient processes
* * * * * /usr/share/astguiclient/ADMIN_keepalive_ALL.pl

### Kill Hangup script for Asterisk updaters
* * * * * /usr/share/astguiclient/AST_manager_kill_hung_congested.pl

### Updater for voicemail
* * * * * /usr/share/astguiclient/AST_vm_update.pl

### Flush queue DB table
11 * * * * /usr/share/astguiclient/AST_flush_DBqueue.pl -q

### Updater for VICIDIAL hopper
* * * * * /usr/share/astguiclient/AST_VDhopper.pl -q

### Inbound email parser
* * * * * /usr/share/astguiclient/AST_inbound_email_parser.pl

### certbot renew
@monthly /usr/src/vicidial-install-scripts/certbot.sh

# =====================================================================
# OFF-PEAK MAINTENANCE JOBS (MST: 11:00 PM - 7:00 AM | UTC: 06:00 - 14:00)
# =====================================================================

### Adjust GMT offset for leads (11:30 PM & 5:30 AM MST)
30 6,12 * * * /usr/share/astguiclient/ADMIN_adjust_GMTnow_on_leads.pl --debug

### Log Table Archiving (12:00 AM MST / 07:00 UTC - 1st of month)
0 7 1 * * /usr/share/astguiclient/ADMIN_archive_log_tables.pl --days=90

### Fix Agent Log (1:00 AM MST / 08:00 UTC)
33 * * * * /usr/share/astguiclient/AST_cleanup_agent_log.pl -one-minute-run
0 8 * * * /usr/share/astguiclient/AST_cleanup_agent_log.pl --last-24hours

### Optimize Database Tables (2:00 AM MST / 09:00 UTC)
0 9 * * * /usr/share/astguiclient/AST_DB_optimize.pl

### Reset Temporary MySQL Info Variables (2:30 AM MST / 09:30 UTC)
30 9 * * * /usr/share/astguiclient/AST_reset_mysql_vars.pl

### Purge Dead Callbacks (3:00 AM MST / 10:00 UTC)
0 10 * * * /usr/share/astguiclient/AST_DB_dead_cb_purge.pl --purge-non-cb -q

### Daily Backups (4:00 AM MST / 11:00 UTC)
0 11 * * * /usr/share/astguiclient/ADMIN_backup.pl

### VICIDIAL Weekly & Daily Agent Reports (4:30 AM MST / 11:30 UTC)
30 11 * * 0 /usr/share/astguiclient/AST_agent_week.pl
30 11 * * * /usr/share/astguiclient/AST_agent_day.pl

### Log File Cleaning (5:00 AM MST / 12:00 UTC)
24 12 * * * /usr/bin/find /var/spool/asterisk/monitorDONE/ORIG -maxdepth 2 -type f -mtime +1 -print | xargs -r rm -f
28 12 * * * /usr/bin/find /var/log/astguiclient -maxdepth 1 -type f -mtime +2 -print | xargs -r rm -f
29 12 * * * /usr/bin/find /var/log/asterisk -maxdepth 3 -type f -mtime +2 -print | xargs -r rm -f
30 12 * * * /usr/bin/find / -maxdepth 1 -name "screenlog.0*" -mtime +4 -print | xargs -r rm -f

### Dialer Inventory Snapshot (6:00 AM MST / 13:00 UTC)
0 13 * * * /usr/share/astguiclient/AST_dialer_inventory_snapshot.pl -q --override-24hours

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

echo "[+] Main server crontab successfully updated."
if [ -n "$BACKUP_FILE" ]; then
    echo "[i] Roll back with: crontab $BACKUP_FILE"
fi

# 3. Configure MariaDB Binary Logging
echo "[+] Setting up MySQL/MariaDB Binary Logging..."

# Locate configuration file
CONF_FILE=""
if [ -f "/etc/my.cnf" ]; then
    CONF_FILE="/etc/my.cnf"
elif [ -f "/etc/mysql/mariadb.conf.d/50-server.cnf" ]; then
    CONF_FILE="/etc/mysql/mariadb.conf.d/50-server.cnf"
elif [ -f "/etc/mysql/my.cnf" ]; then
    CONF_FILE="/etc/mysql/my.cnf"
fi

if [ -z "$CONF_FILE" ]; then
    echo "[!] Could not locate MySQL/MariaDB configuration file. Skipping binlog config." >&2
else
    # Ensure log directory exists with correct permissions
    mkdir -p /var/log/mysql
    chown -R mysql:mysql /var/log/mysql 2>/dev/null || true

    # On SELinux systems (RHEL/AlmaLinux) mysqld needs the mysqld_log_t label
    # on the binlog directory or the service will refuse to start.
    if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
        if command -v semanage >/dev/null 2>&1 && command -v restorecon >/dev/null 2>&1; then
            semanage fcontext -a -t mysqld_log_t '/var/log/mysql(/.*)?' 2>/dev/null || true
            restorecon -R /var/log/mysql 2>/dev/null || true
        else
            echo "[!] SELinux is enforcing but 'semanage' is missing; mysqld may be unable" >&2
            echo "    to write to /var/log/mysql. Install policycoreutils-python-utils." >&2
        fi
    fi

    # Check if binary logging is already configured (an active directive, not a comment)
    if grep -Eq '^[[:space:]]*log_bin[[:space:]]*=' "$CONF_FILE"; then
        echo "[i] Binary logging already enabled in $CONF_FILE."
    else
        echo "[+] Backing up $CONF_FILE to ${CONF_FILE}.bak"
        cp "$CONF_FILE" "${CONF_FILE}.bak"

        # Append parameters under [mysqld]
        if grep -q "^\[mysqld\]" "$CONF_FILE"; then
            sed -i '/^\[mysqld\]/a \
server-id        = 1\
log_bin          = /var/log/mysql/mariadb-bin\
log_bin_index    = /var/log/mysql/mariadb-bin.index\
expire_logs_days = 7\
max_binlog_size  = 100M\
binlog_format    = MIXED' "$CONF_FILE"
        else
            cat << 'MYCNF' >> "$CONF_FILE"

[mysqld]
server-id        = 1
log_bin          = /var/log/mysql/mariadb-bin
log_bin_index    = /var/log/mysql/mariadb-bin.index
expire_logs_days = 7
max_binlog_size  = 100M
binlog_format    = MIXED
MYCNF
        fi
        echo "[+] Binary logging configuration added to $CONF_FILE"

        # Restart MariaDB/MySQL to apply changes (roll the config back on failure)
        DB_SVC=""
        for svc in mariadb mysqld mysql; do
            if systemctl list-unit-files --type=service --no-legend 2>/dev/null | grep -q "^${svc}\.service"; then
                DB_SVC="$svc"
                break
            fi
        done

        if [ -z "$DB_SVC" ]; then
            echo "[!] Could not determine the database service name. Restart MariaDB/MySQL manually to apply." >&2
        else
            echo "[+] Restarting $DB_SVC to apply binary logging..."
            if systemctl restart "$DB_SVC"; then
                echo "[+] $DB_SVC restarted successfully."
            else
                echo "[!] $DB_SVC failed to restart - rolling back ${CONF_FILE}." >&2
                cp -f "${CONF_FILE}.bak" "$CONF_FILE"
                systemctl restart "$DB_SVC" || true
                echo "[!] Configuration rolled back. Binary logging was NOT enabled." >&2
                exit 1
            fi
        fi
    fi
fi

# 4. Verify Binary Logging
if command -v mysql &>/dev/null; then
    echo "[+] Verifying Binary Logging Status:"
    mysql -e "SHOW MASTER STATUS\G" 2>/dev/null || mysql -e "SHOW BINLOG STATUS\G" 2>/dev/null || echo "[!] Unable to fetch binlog status."
fi