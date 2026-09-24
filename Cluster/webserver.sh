#!/usr/bin/env bash
# Script to safely update Main Server crontab with automatic backup

# 1. Create a timestamped backup of the current crontab
BACKUP_FILE="/root/crontab_backup_main_$(date +%Y%m%d_%H%M%S).txt"
crontab -l > "$BACKUP_FILE" 2>/dev/null

if [ -s "$BACKUP_FILE" ]; then
    echo "[+] Current crontab backed up to: $BACKUP_FILE"
else
    echo "[!] Warning: Existing crontab was empty or failed to back up."
fi

# 2. Apply the new optimized crontab
cat << 'EOF' | crontab -
### Audio Sync hourly
* 1 * * * /usr/share/astguiclient/ADMIN_audio_store_sync.pl --upload --quiet

### Daily Backups ###
0 2 * * * /usr/share/astguiclient/ADMIN_backup.pl

### certbot renew
@monthly /usr/src/vicidial-install-scripts/certbot.sh

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

### Fix agent log (Staggered times)
33 * * * * /usr/share/astguiclient/AST_cleanup_agent_log.pl -one-minute-run
15 3 * * * /usr/share/astguiclient/AST_cleanup_agent_log.pl --last-24hours

### Updater for VICIDIAL hopper
* * * * * /usr/share/astguiclient/AST_VDhopper.pl -q

### Adjust GMT offset for leads
1 1,7 * * * /usr/share/astguiclient/ADMIN_adjust_GMTnow_on_leads.pl --debug

### Reset temporary mysql info variables
10 3 * * * /usr/share/astguiclient/AST_reset_mysql_vars.pl

### Optimize database tables
20 3 * * * /usr/share/astguiclient/AST_DB_optimize.pl

### VICIDIAL agent reports
2 0 * * 0 /usr/share/astguiclient/AST_agent_week.pl
30 3 * * * /usr/share/astguiclient/AST_agent_day.pl

### Log cleanup & archiving
24 1 * * * /usr/bin/find /var/spool/asterisk/monitorDONE/ORIG -maxdepth 2 -type f -mtime +1 -print | xargs rm -f
30 1 1 * * /usr/share/astguiclient/ADMIN_archive_log_tables.pl --days=90
28 0 * * * /usr/bin/find /var/log/astguiclient -maxdepth 1 -type f -mtime +2 -print | xargs rm -f
29 0 * * * /usr/bin/find /var/log/asterisk -maxdepth 3 -type f -mtime +2 -print | xargs rm -f
30 0 * * * /usr/bin/find / -maxdepth 1 -name "screenlog.0*" -mtime +4 -print | xargs rm -f

### Purge callbacks
40 3 * * * /usr/share/astguiclient/AST_DB_dead_cb_purge.pl --purge-non-cb -q

### Dialer inventory snapshot
1 7 * * * /usr/share/astguiclient/AST_dialer_inventory_snapshot.pl -q --override-24hours

### Inbound email parser
* * * * * /usr/share/astguiclient/AST_inbound_email_parser.pl

### Dynamic Firewall
@reboot /usr/bin/VB-firewall --whitelist=ViciWhite --dynamic --quiet
* * * * * /usr/bin/VB-firewall --whitelist=ViciWhite --dynamic --quiet
* * * * * sleep 10; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 20; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 30; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 40; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 50; /usr/bin/VB-firewall --white --dynamic --quiet
EOF

echo "[+] Main Server crontab successfully updated!"