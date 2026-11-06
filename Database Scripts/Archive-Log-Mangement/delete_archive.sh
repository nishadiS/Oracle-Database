
#!/bin/ksh
#######################################################################
# Script Name : delete_archive.sh
#
# Description : Deletes Oracle archived redo logs older than 7 days.
#
# Parameters  : -s <ORACLE_SID> (REQUIRED)
#
# Execution   : Scheduled through cron as oracle.
#
# Syntax      : delete_archive.sh -s <ORACLE_SID>
#
# Retention   : 7 days
#######################################################################

#######################################################################
# OS SPECIFIC VARIABLES
#######################################################################

SYSTYPE=$(uname)

if [[ "$SYSTYPE" = "Linux" ]]; then
    DATE_CMD=/bin/date
else
    DATE_CMD=/usr/bin/date
fi

DATE_STRING=$("$DATE_CMD" +%y%m%d_%H%M%S)

#######################################################################
# STATIC VARIABLES
#######################################################################

SCRIPT_HOME=/home/oracle
LOG_DIR=${SCRIPT_HOME}/scripts/log

FSRETENTIONDAYS=7
ARCHIVE_RETENTIONDAYS=7

RUN_LOG_TAG=rman_run_log

#######################################################################
# LOGGING FUNCTION
#######################################################################

log_message()
{
    echo "[$("$DATE_CMD" '+%Y-%m-%d %H:%M:%S')] $1" >> "$RMAN_RUN_LOG"
}

#######################################################################
# EXTRACT COMMAND LINE PARAMETERS
#######################################################################

while getopts ":s:" option
do
    case "$option" in
        s)
            ORACLE_SID="$OPTARG"
            ;;
        :)
            echo "ERROR: Option -$OPTARG requires an argument."
            exit 1
            ;;
        \?)
            echo "ERROR: Invalid command line argument."
            echo "Usage: $0 -s <ORACLE_SID>"
            exit 1
            ;;
    esac
done

shift $((OPTIND - 1))

if [[ -z "$ORACLE_SID" ]]; then
    echo "ERROR: ORACLE_SID is mandatory."
    echo "Usage: $0 -s <ORACLE_SID>"
    exit 1
fi

if [[ $# -ne 0 ]]; then
    echo "ERROR: Unexpected additional arguments."
    exit 1
fi

export ORACLE_SID

LOGFILE=${ORACLE_SID}_${DATE_STRING}.log
RMAN_RUN_LOG=${LOG_DIR}/${RUN_LOG_TAG}_${LOGFILE}
RMAN_LOG=${LOG_DIR}/rman_${LOGFILE}

#######################################################################
# CHECK LOG DIRECTORY
#######################################################################

if [[ ! -d "$LOG_DIR" || ! -w "$LOG_DIR" ]]; then
    echo "ERROR: Log directory does not exist or is not writable: $LOG_DIR"
    exit 1
fi

touch "$RMAN_RUN_LOG"

if [[ $? -ne 0 ]]; then
    echo "ERROR: Unable to create execution log."
    exit 1
fi

log_message "Starting RMAN ARCHIVE LOG DELETE for SID: $ORACLE_SID"

#######################################################################
# LOCATE ORATAB FILE
#######################################################################

if [[ -f /var/opt/oracle/oratab ]]; then
    ORATAB=/var/opt/oracle/oratab
elif [[ -f /etc/oratab ]]; then
    ORATAB=/etc/oratab
else
    log_message "ERROR: Cannot find ORATAB file."
    exit 1
fi

#######################################################################
# VALIDATE SID AND RETRIEVE ORACLE_HOME
#######################################################################

ORACLE_HOME=$(awk -F: -v sid="$ORACLE_SID" '
    $1 == sid && $1 !~ /^#/ {
        print $2
        exit
    }
' "$ORATAB")

if [[ -z "$ORACLE_HOME" ]]; then
    log_message "ERROR: Invalid ORACLE_SID: $ORACLE_SID"
    exit 1
fi

if [[ ! -x "$ORACLE_HOME/bin/rman" ]]; then
    log_message "ERROR: RMAN executable not found in $ORACLE_HOME/bin"
    exit 1
fi

export ORACLE_HOME
export PATH=$ORACLE_HOME/bin:$PATH

log_message "ORACLE_HOME: $ORACLE_HOME"

#######################################################################
# CHECK WHETHER ORACLE INSTANCE IS RUNNING
#######################################################################

ps -ef | awk -v pmon="ora_pmon_${ORACLE_SID}" '
    $NF == pmon { found=1 }
    END { exit !found }
'

if [[ $? -ne 0 ]]; then
    log_message "ERROR: Oracle instance $ORACLE_SID is not running."
    exit 1
fi

log_message "Oracle instance $ORACLE_SID is running."

#######################################################################
# CHECK RMAN CONNECTION AND DELETE ARCHIVE LOGS
#######################################################################

log_message "Starting RMAN archive log cleanup."
log_message "Archive log retention period: ${ARCHIVE_RETENTIONDAYS} days."

"$ORACLE_HOME/bin/rman" log="$RMAN_LOG" <<EOF >> "$RMAN_RUN_LOG" 2>&1
CONNECT TARGET /

SET ECHO ON

RUN
{
    CROSSCHECK ARCHIVELOG ALL;

    DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;

    DELETE NOPROMPT ARCHIVELOG ALL
    COMPLETED BEFORE 'SYSDATE-${ARCHIVE_RETENTIONDAYS}';
}

EXIT;
EOF

RMAN_STATUS=$?

#######################################################################
# CHECK RMAN EXECUTION STATUS
#######################################################################

if [[ $RMAN_STATUS -ne 0 ]]; then

    log_message "RMAN Archivelog Delete Status: FAIL"
    log_message "RMAN returned exit code: $RMAN_STATUS"
    log_message "Check RMAN log: $RMAN_LOG"

    exit 1

fi

# Additional check for reported RMAN/Oracle errors

if grep -E 'RMAN-00569|RMAN-03002|ORA-[0-9]{5}' "$RMAN_LOG" \
    > /dev/null 2>&1; then

    log_message "RMAN Archivelog Delete Status: FAIL"
    log_message "RMAN/ORA errors detected. Check: $RMAN_LOG"

    exit 1

fi

log_message "RMAN Archivelog Delete Status: SUCCESS"

#######################################################################
# RMAN LOG CLEANUP
#######################################################################

log_message "Starting old RMAN log cleanup."

find "$LOG_DIR" -type f \
    -name "${RUN_LOG_TAG}_${ORACLE_SID}_*.log" \
    -mtime +${FSRETENTIONDAYS} \
    -exec rm -f {} \;

find "$LOG_DIR" -type f \
    -name "rman_${ORACLE_SID}_*.log" \
    -mtime +${FSRETENTIONDAYS} \
    -exec rm -f {} \;

#######################################################################
# END
#######################################################################

log_message "Completed RMAN ARCHIVE LOG DELETE for SID: $ORACLE_SID"
log_message "Execution completed successfully."

exit 0
