
# Oracle RMAN Incremental Hot Backup Automation

## Overview

This repository contains a KornShell-based automation utility for performing Oracle Database online backups using Recovery Manager (RMAN).

The script supports RMAN Level 0, Level 1 cumulative incremental backups, and archived redo log-only backups.

It is designed to automate database backup operations through UNIX/Linux cron scheduling while maintaining backup execution logs and status notifications.

## Features

- RMAN Level 0 database backups.
- RMAN Level 1 cumulative incremental backups.
- Archived redo log-only backups.
- Online database backup without database downtime.
- Automatic Oracle Home identification using ORATAB.
- Oracle instance availability verification.
- Automatic Block Change Tracking status check and enablement.
- Configurable RMAN channel parallelism.
- Backup compression support.
- Configurable backup piece size.
- Automatic backup directory creation.
- RMAN backup execution logging.
- Backup status reporting.
- Email notification support.
- Historical backup and log cleanup.

## Backup Types

| Backup Type | Parameter | Description |
|---|---|---|
| Level 0 | `-l 0` | Baseline incremental backup |
| Level 1 | `-l 1` | Cumulative incremental backup |
| Archive Log Only | `-l a` | Backs up archived redo logs |

## Requirements

- Oracle Database in ARCHIVELOG mode for online database backups.
- Oracle Recovery Manager (RMAN).
- Linux/Unix operating system.
- KornShell (`ksh`).
- Oracle software owner privileges.
- SQL*Plus.
- Configured backup storage location.
- `mailx` for email notifications (if enabled).

## Usage

### Level 0 Backup

```bash
./rman_incremental_hot_backup.sh -s ORACLE_SID -l 0
```

### Level 1 Cumulative Incremental Backup

```bash
./rman_incremental_hot_backup.sh -s ORACLE_SID -l 1
```

### Archive Log Only Backup

```bash
./rman_incremental_hot_backup.sh -s ORACLE_SID -l a
```

## Optional Parameters

| Parameter | Description |
|---|---|
| `-s` | Oracle SID |
| `-l` | Backup level: 0, 1, or a |
| `-r` | Recovery window configuration |
| `-p` | RMAN channel parallelism |
| `-m` | Maximum backup piece size in GB |
| `-c` | Enable RMAN compressed backupsets |
| `-n` | Disable RMAN recovery catalog usage |

## Backup Configuration

The script includes configurable parameters for:

- RMAN channel parallelism.
- Backup piece size.
- Backup retention configuration.
- Backup compression.
- Backup storage location.
- Execution log retention.

Default values should be reviewed and adjusted according to the database environment.

## Backup Storage

Backup directories are organized by database name and backup type.

The script creates separate directories for:

- Level 0 backups.
- Level 1 backups.
- Archived redo log-only backups.

## Logging and Monitoring

The script generates execution logs containing backup start and end timestamps, backup directory information, backup tags, and execution status.

RMAN execution logs are maintained separately to support troubleshooting and backup verification.

Email notifications can be configured to report backup failures.

## Scheduling

Example cron entries:

```bash
# Weekly Level 0 backup
0 1 * * 0 /home/oracle/bin/rman_incremental_hot_backup.sh -s ORCL -l 0

# Daily Level 1 backup
0 1 * * 1-6 /home/oracle/bin/rman_incremental_hot_backup.sh -s ORCL -l 1

# Archive log backup
0 */2 * * * /home/oracle/bin/rman_incremental_hot_backup.sh -s ORCL -l a
```

These are illustrative schedules and should be adjusted according to the backup strategy and recovery requirements.

## Important Considerations

- Validate backup retention policies before implementation.
- Ensure sufficient backup storage capacity.
- Monitor RMAN execution logs and backup completion status.
- Validate backup integrity using RMAN validation and restore testing.
- Review archived redo log deletion behavior before enabling automated cleanup.
- Test the script in a non-production environment before production deployment.

## Disclaimer

This script is provided as an Oracle DBA automation example. Review all environment-specific configurations, backup policies, and deletion operations before using it in production.
