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
`00:00`–`00:05 UTC` batch lands at **06:00**–**06:05 Dhaka time** — exactly the
window the client reports.

## What the scripts do

| Script | Run on | Effect |
| --- | --- | --- |
| `Cluster/webserver.sh` | Main / Web / DB server | Keeps all cluster-wide DB + report jobs, but staggers them into off-peak hours |
| `Cluster/dailerserver.sh` | Every Dialer / Asterisk node | Keeps only node-local jobs (audio mix/compress, keepalives, local log purge) and removes the duplicated cluster-wide DB jobs |

Both scripts write a timestamped backup of the existing crontab to
`/root/crontab_backup_*.txt` **before** changing anything, and refuse to run
unless they are root.

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
