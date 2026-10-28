#!/bin/bash
set -u

lastLogfile="/var/log/backup-last.log"

# Word-split on purpose: each variable may hold several paths or arguments.
read -r -a backupSources <<< "${BACKUP_SOURCES:-/data}"
read -r -a jobArgs <<< "${RESTIC_JOB_ARGS:-}"
read -r -a forgetArgs <<< "${RESTIC_FORGET_ARGS:-}"

copyErrorLog() {
  cp "$lastLogfile" /var/log/backup-error-last.log
}

logLast() {
  echo "$1" >> "$lastLogfile"
}

if [[ -f "/hooks/pre-backup.sh" ]]; then
    echo "Starting pre-backup script ..."
    if ! /hooks/pre-backup.sh; then
      echo "pre-backup script failed. Exit 1"
      exit 1
    fi
else
    echo "Pre-backup script not found ..."
fi

start=$(date +%s)
rm -f "$lastLogfile"
echo "Starting Backup at $(date +"%Y-%m-%d %H:%M:%S")"
echo "Starting Backup at $(date)" >> "$lastLogfile"
logLast "BACKUP_CRON: ${BACKUP_CRON:-}"
logLast "RESTIC_TAG: ${RESTIC_TAG:-}"
logLast "RESTIC_FORGET_ARGS: ${RESTIC_FORGET_ARGS:-}"
logLast "RESTIC_JOB_ARGS: ${RESTIC_JOB_ARGS:-}"
logLast "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"

# Do not save full backup log to logfile but to backup-last.log
restic backup "${backupSources[@]}" "${jobArgs[@]}" --tag="${RESTIC_TAG?"Missing environment variable RESTIC_TAG"}" >> "$lastLogfile" 2>&1
backupRC=$?
logLast "Finished backup at $(date)"
if [[ $backupRC -eq 0 ]]; then
    echo "Backup Successful"
else
    echo "Backup Failed with Status ${backupRC}"
    restic unlock
    copyErrorLog
fi

forgetRC=0
if [[ $backupRC -eq 0 && ${#forgetArgs[@]} -gt 0 ]]; then
    echo "Forget about old snapshots based on RESTIC_FORGET_ARGS = ${RESTIC_FORGET_ARGS}"
    restic forget "${forgetArgs[@]}" >> "$lastLogfile" 2>&1
    forgetRC=$?
    logLast "Finished forget at $(date)"
    if [[ $forgetRC -eq 0 ]]; then
        echo "Forget Successful"
    else
        echo "Forget Failed with Status ${forgetRC}"
        restic unlock
        copyErrorLog
    fi
fi

end=$(date +%s)
echo "Finished Backup at $(date +"%Y-%m-%d %H:%M:%S") after $((end-start)) seconds"

if [[ -f "/hooks/post-backup.sh" ]]; then
    echo "Starting post-backup script ..."
    /hooks/post-backup.sh "$backupRC"
else
    echo "Post-backup script not found ..."
fi

# Report the run to the caller (a host unit running /bin/backup via docker
# exec): the backup's status first, else the forget's.
if [[ $backupRC -ne 0 ]]; then
    exit "$backupRC"
fi
exit "$forgetRC"
