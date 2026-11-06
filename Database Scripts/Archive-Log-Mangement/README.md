
# Oracle Archive Log Management

## Overview

This repository contains Oracle Database archive log management scripts and automation utilities using Recovery Manager (RMAN).

The objective is to simplify archive log maintenance, optimize storage utilization, and support routine Oracle Database administration activities.

## Scripts

| Script | Description |
|---|---|
| `delete_archive.sh` | Automates the deletion of archived redo logs older than the configured retention period using RMAN. |

## Features

- Automated archive log cleanup using RMAN.
- Configurable archive log retention period.
- Oracle SID validation using ORATAB.
- Automatic Oracle Home identification.
- Oracle instance availability verification.
- RMAN crosscheck and expired archive log cleanup.
- Execution logging and error handling.
- Automated log file cleanup.

## Requirements

- Oracle Database
- Oracle Recovery Manager (RMAN)
- Linux/Unix operating system
- KornShell (`ksh`)
- Oracle software owner privileges

## Usage

```bash
./delete_archive.sh -s ORACLE_SID
```

Example:

```bash
./delete_archive.sh -s ORCL
```

## Scheduling

Example cron entry to execute the script daily at 2:00 AM:

```bash
0 2 * * * /home/oracle/scripts/bin/delete_archive.sh -s ORCL
```

## Important Considerations

- Review archive log backup requirements before deletion.
- Consider Data Guard and other downstream dependencies.
- Validate the retention period against recovery requirements.
- Test in a non-production environment before production deployment.

  
## Execution Flow

The following flowchart illustrates the execution process of the archive log cleanup script.

```mermaid
flowchart TD
    A([Start]) --> B[Read command-line parameters]
    B --> C{Valid ORACLE_SID provided?}

    C -- No --> X[Display error and exit]
    C -- Yes --> D[Locate ORATAB file]

    D --> E{ORATAB found?}
    E -- No --> X
    E -- Yes --> F[Validate ORACLE_SID and retrieve ORACLE_HOME]

    F --> G{Valid SID and ORACLE_HOME?}
    G -- No --> X
    G -- Yes --> H[Verify RMAN executable]

    H --> I{RMAN available?}
    I -- No --> X
    I -- Yes --> J[Check Oracle instance status]

    J --> K{Instance running?}
    K -- No --> X
    K -- Yes --> L[Connect to RMAN]

    L --> M[Crosscheck archived redo logs]
    M --> N[Delete expired archive log records]
    N --> O[Delete archived logs older than 7 days]

    O --> P{RMAN execution successful?}
    P -- No --> Q[Log failure details]
    P -- Yes --> R[Clean up old execution and RMAN logs]

    R --> S[Write completion status]
    S --> T([End])
    Q --> T
    X --> T
```


## Disclaimer

These scripts are provided for educational and DBA automation purposes. Review and validate all configurations before using them in production environments.
