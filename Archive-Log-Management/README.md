</Oracle Database Archive Log Cleanup Automation Using RMAN

This script automates Oracle Database archived redo log cleanup using Recovery Manager (RMAN).It identifies archived redo logs older than the configured retention period, performs an RMAN crosscheck, removes expired archive log records, and deletes eligible archived logs.The script is designed to simplify routine Oracle database administration and maintain archive log storage efficiently.

---Features

Automated archived redo log cleanup using RMAN.
Configurable archive log retention period.
Oracle SID validation using the ORATAB file.
Automatic Oracle Home identification.
Oracle instance availability verification.
RMAN crosscheck and expired archive log cleanup.
Execution status and error logging.
Automatic cleanup of historical execution logs.
Cron scheduling support.

---Requirements

Oracle Database.
Oracle Recovery Manager (RMAN).
Linux/Unix operating system.
KornShell (ksh).
Oracle software owner privileges.

---Configuration

Update the following variables according to your environment:

SCRIPT_HOME: Oracle user's home directory.
LOG_DIR: Directory used to store execution and RMAN logs.
ARCHIVE_RETENTIONDAYS: Archived redo log retention period.
FSRETENTIONDAYS: Execution log retention period.
Default archive log retention: 7 days.

---Usage

./delete_archive.sh -s ORACLE_SID

Example:

./delete_archive.sh -s ORCL

---RMAN Operations

The script performs the following operations:
 Connects to the target database using OS authentication.
 Crosschecks all archived redo logs.
 Deletes expired archived redo log records.
 Deletes archived redo logs completed before the configured retention threshold.

---Cron Scheduling
Example cron configuration to execute the script daily at 2:00 AM:
0 2 * * * /home/oracle/scripts/bin/delete_archive.sh -s ORCL

---Logging
The script generates separate execution and RMAN logs to facilitate troubleshooting and execution monitoring.

---Important Considerations
Review archive log backup requirements before enabling deletion.Ensure archived redo logs are not required by Data Guard, GoldenGate, or other downstream processes.
Validate the retention period against database recovery requirements.Test the script in a non-production environment before production deployment.

---Disclaimer

This script is provided as a DBA automation example. Review and validate the configuration and deletion criteria before using it in any production environment. />
