#!/bin/ksh
#
# Script Name : rman_incremental_hot_backup.sh
# Purpose     : Run Oracle RMAN Level 0, Level 1 cumulative, or
#               archived-log-only backups.
#
# Usage:
#   rman_incremental_hot_backup.sh -s ORACLE_SID -l 0|1|a
#       [-p CHANNELS] [-m MAX_PIECE_SIZE_GB] [-c]
#
# Examples:
#   ./rman_incremental_hot_backup.sh -s ORCL -l 0
#   ./rman_incremental_hot_backup.sh -s ORCL -l 1 -p 4 -m 8 -c
#   ./rman_incremental_hot_backup.sh -s ORCL -l a
#
# Run as the Oracle software owner. Review all settings before production use.
#

###############################################################################
# Configuration - customize these values for your environment.
###############################################################################

ORACLE_BASE_HOME="${ORACLE_BASE_HOME:-/home/oracle}"
LOG_DIR="${LOG_DIR:-${ORACLE_BASE_HOME}/rman-logs}"
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/u01/backup}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-10}"

# Set to YES only after confirming that backed-up archived logs may be removed.
# Default NO is deliberately conservative.
DELETE_ARCHIVELOG_INPUT="${DELETE_ARCHIVELOG_INPUT:-NO}"

# Optional email notification. Configure MAIL_LIST and ensure mailx is installed.
SEND_EMAIL="${SEND_EMAIL:-NO}"
MAIL_LIST="${MAIL_LIST:-}"

###############################################################################
# Utility functions
###############################################################################

timestamp()
{
    date '+%Y-%m-%d %H:%M:%S'
}

log()
{
    print -- "[$(timestamp)] $*" >> "$RUN_LOG"
}

fail()
{
    log "ERROR: $*"
    print -- "ERROR: $*" >&2
    exit 1
}

usage()
{
    cat <<USAGE
Usage: $0 -s ORACLE_SID -l 0|1|a [-p CHANNELS] [-m MAX_PIECE_SIZE_GB] [-c]

  -s  Oracle SID (required)
  -l  Backup type: 0=Level 0, 1=Level 1 cumulative, a=archivelog only
  -p  RMAN disk channel count (default: 2)
  -m  Maximum backup piece size in GB (default: 8)
  -c  Use compressed backupsets
USAGE
}

###############################################################################
# Parse and validate parameters
###############################################################################

ORACLE_SID=""
LEVEL=""
PARALLEL=2
MAXPIECESIZE=8
COMPRESS=""

while getopts ":s:l:p:m:ch" option
do
    case "$option" in
        s) ORACLE_SID="$OPTARG" ;;
        l) LEVEL="$OPTARG" ;;
        p) PARALLEL="$OPTARG" ;;
        m) MAXPIECESIZE="$OPTARG" ;;
        c) COMPRESS="YES" ;;
        h) usage; exit 0 ;;
        :) usage; fail "Option -$OPTARG requires an argument." ;;
        \?) usage; fail "Invalid option: -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))

[[ $# -eq 0 ]] || { usage; fail "Unexpected positional argument(s)."; }
[[ -n "$ORACLE_SID" ]] || { usage; fail "Oracle SID (-s) is required."; }
[[ "$LEVEL" = "0" || "$LEVEL" = "1" || "$LEVEL" = "a" || "$LEVEL" = "A" ]] ||
    { usage; fail "Backup level must be 0, 1, or a."; }

# Restrict SID characters to avoid unsafe SQL/RMAN substitutions.
case "$ORACLE_SID" in
    *[!A-Za-z0-9_\$#]*|"") fail "Invalid characters in ORACLE_SID." ;;
esac

case "$PARALLEL" in
    ''|*[!0-9]*) fail "Channel count must be a positive integer." ;;
esac
(( PARALLEL >= 1 && PARALLEL <= 32 )) || fail "Channel count must be between 1 and 32."

case "$MAXPIECESIZE" in
    ''|*[!0-9]*) fail "Maximum piece size must be a positive integer (GB)." ;;
esac
(( MAXPIECESIZE >= 1 )) || fail "Maximum piece size must be greater than zero."

###############################################################################
# Initialize paths and logs
###############################################################################

HOST=$(hostname)
DATE_STRING=$(date '+%y%m%d_%H%M%S')
DATE_DAY=$(date '+%Y%m%d')
LOGFILE="${ORACLE_SID}_${DATE_STRING}.log"

mkdir -p "$LOG_DIR" || { print "ERROR: Cannot create log directory: $LOG_DIR" >&2; exit 1; }
[[ -d "$LOG_DIR" && -w "$LOG_DIR" ]] || { print "ERROR: Log directory is not writable: $LOG_DIR" >&2; exit 1; }

RUN_LOG="${LOG_DIR}/rman_run_log_${LOGFILE}"
touch "$RUN_LOG" || { print "ERROR: Cannot create $RUN_LOG" >&2; exit 1; }

log "Starting RMAN backup. SID=$ORACLE_SID LEVEL=$LEVEL HOST=$HOST"

###############################################################################
# Locate ORATAB and determine ORACLE_HOME using an exact SID match
###############################################################################

if [[ -f /etc/oratab ]]; then
    ORATAB="/etc/oratab"
elif [[ -f /var/opt/oracle/oratab ]]; then
    ORATAB="/var/opt/oracle/oratab"
else
    fail "Cannot find /etc/oratab or /var/opt/oracle/oratab."
fi

ORACLE_HOME=$(awk -F: -v sid="$ORACLE_SID" '
    $1 == sid && $1 !~ /^[[:space:]]*#/ && $2 != "" { print $2; exit }
' "$ORATAB")

[[ -n "$ORACLE_HOME" ]] || fail "SID $ORACLE_SID was not found in $ORATAB."
[[ -x "$ORACLE_HOME/bin/sqlplus" ]] || fail "SQL*Plus not found under ORACLE_HOME=$ORACLE_HOME."
[[ -x "$ORACLE_HOME/bin/rman" ]] || fail "RMAN not found under ORACLE_HOME=$ORACLE_HOME."

export ORACLE_SID ORACLE_HOME
PATH="$ORACLE_HOME/bin:/usr/bin:/bin"
export PATH

###############################################################################
# Verify local instance is running
###############################################################################

ps -ef | awk -v pmon="ora_pmon_${ORACLE_SID}" '$NF == pmon { found=1 } END { exit !found }'
[[ $? -eq 0 ]] || fail "Instance $ORACLE_SID does not appear to be running on this host."

###############################################################################
# Obtain database name and DBID; fail on SQL*Plus errors
###############################################################################

DB_INFO_FILE="${LOG_DIR}/.dbinfo_${ORACLE_SID}_$$"
trap 'rm -f "$DB_INFO_FILE"; [[ -n "$LOCK_DIR" ]] && rmdir "$LOCK_DIR" 2>/dev/null' 0 1 2 15

"$ORACLE_HOME/bin/sqlplus" -s -L "/ as sysdba" > "$DB_INFO_FILE" 2>&1 <<'SQL'
WHENEVER OSERROR EXIT FAILURE
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF VERIFY OFF ECHO OFF TRIMSPOOL ON
SELECT name || '|' || dbid FROM v$database;
EXIT
SQL
SQL_STATUS=$?

[[ $SQL_STATUS -eq 0 ]] || {
    cat "$DB_INFO_FILE" >> "$RUN_LOG"
    fail "Unable to retrieve database name and DBID through SQL*Plus."
}

DB_INFO=$(awk 'NF {print; exit}' "$DB_INFO_FILE")
DB_NAME=${DB_INFO%%|*}
DBID=${DB_INFO#*|}
[[ -n "$DB_NAME" && -n "$DBID" && "$DB_INFO" = *"|"* ]] ||
    fail "Could not parse database name and DBID from SQL*Plus output."
rm -f "$DB_INFO_FILE"

log "Database name=$DB_NAME DBID=$DBID"
log "ORACLE_HOME=$ORACLE_HOME"

###############################################################################
# Prevent concurrent executions for the same SID on this host
###############################################################################

LOCK_DIR="${LOG_DIR}/.${ORACLE_SID}_rman_backup.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    fail "A backup lock already exists ($LOCK_DIR). Confirm no backup is running before removing a stale lock."
fi

###############################################################################
# Prepare backup directories
###############################################################################

BACKUP_DB_DIR="${BACKUP_BASE_DIR}/${DB_NAME}"
mkdir -p "$BACKUP_DB_DIR" || fail "Cannot create database backup directory: $BACKUP_DB_DIR"

if [[ "$LEVEL" = "a" || "$LEVEL" = "A" ]]; then
    BACKUP_DIR="${BACKUP_DB_DIR}/ARCH_${DATE_DAY}_${DATE_STRING}"
    BACKUP_TYPE="ARCHIVELOG_ONLY"
else
    BACKUP_DIR="${BACKUP_DB_DIR}/LEVEL${LEVEL}_${DATE_STRING}"
    BACKUP_TYPE="LEVEL${LEVEL}"
fi

mkdir -p "$BACKUP_DIR" || fail "Cannot create backup directory: $BACKUP_DIR"
RMAN_LOG="${BACKUP_DIR}/rman_${LOGFILE}"

log "Backup type=$BACKUP_TYPE"
log "Backup directory=$BACKUP_DIR"
log "RMAN channels=$PARALLEL; max piece size=${MAXPIECESIZE}G; compressed=$([[ -n "$COMPRESS" ]] && print YES || print NO)"

###############################################################################
# Check database ARCHIVELOG mode for online database backup
###############################################################################

if [[ "$LEVEL" != "a" && "$LEVEL" != "A" ]]; then
    ARCHIVE_MODE=$("$ORACLE_HOME/bin/sqlplus" -s -L "/ as sysdba" <<'SQL'
WHENEVER OSERROR EXIT FAILURE
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF VERIFY OFF
SELECT log_mode FROM v$database;
EXIT
SQL
)
    SQL_STATUS=$?
    [[ $SQL_STATUS -eq 0 ]] || fail "Unable to determine database log mode."
    print -- "$ARCHIVE_MODE" | grep -qi ARCHIVELOG ||
        fail "Database is not in ARCHIVELOG mode; online database backup was not started."
fi

###############################################################################
# Check Block Change Tracking (report status; do not change database state)
###############################################################################

BCT_STATUS=$("$ORACLE_HOME/bin/sqlplus" -s -L "/ as sysdba" <<'SQL'
WHENEVER OSERROR EXIT FAILURE
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET PAGESIZE 0 FEEDBACK OFF HEADING OFF VERIFY OFF
SELECT status FROM v$block_change_tracking;
EXIT
SQL
)
SQL_STATUS=$?
if [[ $SQL_STATUS -eq 0 ]]; then
    log "Block Change Tracking status: $(print -- "$BCT_STATUS" | awk 'NF {print; exit}')"
else
    log "WARNING: Unable to retrieve Block Change Tracking status. Continuing."
fi

###############################################################################
# Build RMAN command file
###############################################################################

RMAN_CMD="${BACKUP_DIR}/rman_commands_${DATE_STRING}.rcv"
: > "$RMAN_CMD" || fail "Cannot create RMAN command file."

{
    print "CONNECT TARGET /;"
    print "SET ECHO ON;"
    print "RUN {"
    print "  ALLOCATE CHANNEL ch00 DEVICE TYPE DISK MAXPIECESIZE ${MAXPIECESIZE}G;"
    if (( PARALLEL > 1 )); then
        i=1
        while (( i < PARALLEL )); do
            printf '  ALLOCATE CHANNEL ch%02d DEVICE TYPE DISK MAXPIECESIZE %sG;\n' "$i" "$MAXPIECESIZE"
            (( i = i + 1 ))
        done
    fi

    if [[ "$LEVEL" = "a" || "$LEVEL" = "A" ]]; then
        if [[ -n "$COMPRESS" ]]; then
            print "  BACKUP AS COMPRESSED BACKUPSET ARCHIVELOG ALL FORMAT '${BACKUP_DIR}/arc_%d_%T_%U' TAG 'ARCH_${DATE_STRING}'$( [[ "$DELETE_ARCHIVELOG_INPUT" = "YES" ]] && print ' DELETE INPUT' );"
        else
            print "  BACKUP ARCHIVELOG ALL FORMAT '${BACKUP_DIR}/arc_%d_%T_%U' TAG 'ARCH_${DATE_STRING}'$( [[ "$DELETE_ARCHIVELOG_INPUT" = "YES" ]] && print ' DELETE INPUT' );"
        fi
    else
        if [[ -n "$COMPRESS" ]]; then
            print "  BACKUP AS COMPRESSED BACKUPSET INCREMENTAL LEVEL ${LEVEL}"
        else
            print "  BACKUP INCREMENTAL LEVEL ${LEVEL}"
        fi
        if [[ "$LEVEL" = "1" ]]; then
            print "    CUMULATIVE"
        fi
        print "    DATABASE INCLUDE CURRENT CONTROLFILE"
        print "    FORMAT '${BACKUP_DIR}/db_%d_%T_%U'"
        print "    TAG 'LEVEL${LEVEL}_${DATE_STRING}'"
        if [[ "$DELETE_ARCHIVELOG_INPUT" = "YES" ]]; then
            print "    PLUS ARCHIVELOG FORMAT '${BACKUP_DIR}/arc_%d_%T_%U' DELETE INPUT;"
        else
            print "    PLUS ARCHIVELOG FORMAT '${BACKUP_DIR}/arc_%d_%T_%U';"
        fi

        print "  BACKUP CURRENT CONTROLFILE FORMAT '${BACKUP_DIR}/controlfile_%d_%T_%U' TAG 'CTRL_${DATE_STRING}';"
    fi

    print "  RELEASE CHANNEL ch00;"
    if (( PARALLEL > 1 )); then
        i=1
        while (( i < PARALLEL )); do
            printf '  RELEASE CHANNEL ch%02d;\n' "$i"
            (( i = i + 1 ))
        done
    fi
    print "}"
    print "EXIT;"
} >> "$RMAN_CMD"

###############################################################################
# Execute RMAN and record the actual process exit status
###############################################################################

log "Starting RMAN operation."
"$ORACLE_HOME/bin/rman" log="$RMAN_LOG" cmdfile="$RMAN_CMD" >> "$RUN_LOG" 2>&1
RMAN_STATUS=$?

if [[ $RMAN_STATUS -ne 0 ]]; then
    log "BACKUP STATUS: FAILED (RMAN exit code $RMAN_STATUS)"
    [[ -f "$RMAN_LOG" ]] && cat "$RMAN_LOG" >> "$RUN_LOG"
    EMAIL_SUBJECT="RMAN backup FAILED: ${ORACLE_SID} on ${HOST} (${DATE_STRING})"
    FINAL_STATUS=1
else
    # RMAN can sometimes return a zero process status while logging an RMAN/ORA error.
    if grep -E 'RMAN-00569|RMAN-03002|RMAN-03009|ORA-[0-9]{5}' "$RMAN_LOG" >/dev/null 2>&1; then
        log "BACKUP STATUS: WARNING/FAILED - RMAN or ORA messages found; inspect RMAN log."
        EMAIL_SUBJECT="RMAN backup requires review: ${ORACLE_SID} on ${HOST} (${DATE_STRING})"
        FINAL_STATUS=1
    else
        log "BACKUP STATUS: SUCCESS"
        EMAIL_SUBJECT="RMAN backup SUCCESS: ${ORACLE_SID} on ${HOST} (${DATE_STRING})"
        FINAL_STATUS=0
    fi
fi

###############################################################################
# Retain copies of RMAN logs and clean up old logs
###############################################################################

cp "$RMAN_LOG" "$LOG_DIR/" 2>/dev/null
find "$LOG_DIR" -type f \( -name "rman_run_log_${ORACLE_SID}_*.log" -o -name "rman_${ORACLE_SID}_*.log" \) \
    -mtime +"$LOG_RETENTION_DAYS" -exec rm -f {} \;

log "RMAN log: $RMAN_LOG"
log "Backup job finished with status=$FINAL_STATUS"

###############################################################################
# Optional email notification
###############################################################################

if [[ "$SEND_EMAIL" = "YES" && -n "$MAIL_LIST" ]]; then
    if command -v mailx >/dev/null 2>&1; then
        mailx -s "$EMAIL_SUBJECT" "$MAIL_LIST" < "$RUN_LOG"
    else
        log "WARNING: SEND_EMAIL=YES but mailx is not installed."
    fi
fi

exit "$FINAL_STATUS"
