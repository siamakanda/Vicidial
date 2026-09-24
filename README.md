# VICIdial Cluster Crontab Optimization

Bash scripts that fix the recurring daily performance lag in a VICIdial cluster
(slow reports, agent screens taking long to load or update).

## Why the cluster lags

A stock VICIdial install drops the **same** crontab on **every** server. In a
cluster that means all nodes fire the heavy, database-locking maintenance jobs
at the same minute — so the primary database is hit by every node at once:

- `AST_cleanup_agent_log.pl --last-24hours`
- `AST_agent_day.pl`
- `AST_DB_optimize.pl` (`OPTIMIZE TABLE` locks tables cluster-wide)
- `AST_reset_mysql_vars.pl`
- `AST_DB_dead_cb_purge.pl`
- log / recording purge `find ... | xargs rm`

The cluster's cron runs in **UTC** while the client is **UTC+6**, so the
default `00:00`–`00:05 UTC` batch lands at **06:00**–**06:05 Dhaka time** —
exactly the window the client reports. The fix moves every heavy job into the
client's quiet hours (see [Off-peak window](#off-peak-window)).

## What the scripts do

| Script | Run on | Effect |
| --- | --- | --- |
| `Cluster/webserver.sh` | Main / Web / DB server | Keeps all cluster-wide DB + report jobs (staggered off-peak) **and enables MariaDB binary logging** (restarts the DB service) |
| `Cluster/dailerserver.sh` | Every Dialer / Asterisk node | Keeps only node-local jobs (audio mix/compress, keepalives, local log purge) and removes the duplicated cluster-wide DB jobs |

Both scripts write a timestamped backup of the existing crontab to
`/root/crontab_backup_*.txt` **before** changing anything, and refuse to run
unless they are root.

## Off-peak window

The heavy maintenance jobs are pinned to the client's quiet hours —
**11:00 PM – 7:00 AM MST**, which is **06:00 – 14:00 UTC** on the cluster's
cron clock:

| Job (main server) | UTC | MST |
| --- | --- | --- |
| `ADMIN_adjust_GMTnow_on_leads.pl` | 06:30 & 12:30 | 11:30 PM & 5:30 AM |
| `ADMIN_archive_log_tables.pl` (1st) | 07:00 | 12:00 AM |
| `AST_cleanup_agent_log.pl --last-24hours` | 08:00 | 1:00 AM |
| `AST_DB_optimize.pl` | 09:00 | 2:00 AM |
| `AST_reset_mysql_vars.pl` | 09:30 | 2:30 AM |
| `AST_DB_dead_cb_purge.pl` | 10:00 | 3:00 AM |
| `ADMIN_backup.pl` | 11:00 | 4:00 AM |
| `AST_agent_week.pl` / `AST_agent_day.pl` | 11:30 | 4:30 AM |
| log / recording purge | 12:00 | 5:00 AM |
| `AST_dialer_inventory_snapshot.pl` | 13:00 | 6:00 AM |

Each job sits on its own minute so no two cluster-wide locks line up. On a
dialer node `dailerserver.sh` prompts for the off-peak start hour (UTC) and
runs only the node-local cleanup there.

## Main server also enables MariaDB binary logging

On the main server, `webserver.sh` additionally prepares the replication master:
it adds `server-id`, `log_bin`, `log_bin_index`, `expire_logs_days`,
`max_binlog_size` and `binlog_format` under `[mysqld]` (saving the config to
`<file>.bak` first), labels `/var/log/mysql` for SELinux, and restarts
MariaDB/MySQL to apply it.

> **This restarts the database** - run it in a maintenance window. If the
> service fails to restart, the script restores the config backup automatically
> and exits with an error.
>
> If binary logging is already configured, no changes are made. Note
> `expire_logs_days` is deprecated on MySQL 8.4+ / MariaDB 10.6+
> (`binlog_expire_logs_seconds` is the modern equivalent).

## Requirements

- Linux (AlmaLinux / CentOS / Debian / Ubuntu).
- Run as `root` (or with `sudo`).
- VICIdial installed with its scripts in `/usr/share/astguiclient`.

## Deployment

### 1. Main / Web / DB server

Run on the main VICIdial server (Web / Master DB / Admin node):

```bash
curl -sSL https://raw.githubusercontent.com/siamakanda/Vicidial/main/Cluster/webserver.sh | sudo bash
```

or with `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/siamakanda/Vicidial/main/Cluster/webserver.sh | sudo bash
```

### 2. Dialer nodes

Run on **every** Asterisk / Dialer node in the cluster:

```bash
curl -sSL https://raw.githubusercontent.com/siamakanda/Vicidial/main/Cluster/dailerserver.sh | sudo bash
```

or with `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/siamakanda/Vicidial/main/Cluster/dailerserver.sh | sudo bash
```

### Manual (clone) method

```bash
git clone https://github.com/siamakanda/Vicidial.git
cd Vicidial/Cluster

sudo bash webserver.sh     # on the main server
sudo bash dailerserver.sh  # on each dialer node
```

Each run ends with the path of the backup file it created, for example:

```
[+] Existing crontab backed up to: /root/crontab_backup_main_20250924_060500.txt
[+] Main server crontab successfully updated.
[i] Roll back with: crontab /root/crontab_backup_main_20250924_060500.txt
```

## Verify

Confirm the new schedule is active on a node:

```bash
crontab -l
```

The dialer nodes should no longer contain `AST_DB_optimize.pl`,
`AST_cleanup_agent_log.pl`, `AST_reset_mysql_vars.pl`, `AST_DB_dead_cb_purge.pl`
or `AST_agent_day.pl`.

## Rollback

Every run leaves a timestamped backup in `/root/`. Restore a specific one:

```bash
ls -lt /root/crontab_backup_*.txt   # newest first
crontab /root/crontab_backup_main_20250924_060500.txt
```

Or restore the most recent backup automatically:

```bash
crontab "$(ls -t /root/crontab_backup_*.txt | head -n1)"
```

## Optional: capture slow queries

On the database server, log any query taking longer than 2 seconds while you
validate the fix:

```sql
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;
```

The log is written to `/var/log/mariadb/mariadb-slow.log` (or
`/var/log/mysql/mysql-slow.log` on MySQL).
