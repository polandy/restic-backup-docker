#!/bin/bash
set -u

lastLogfile="/var/log/backup-last.log"
# restic's --json output of the last run; its summary feeds the summary line.
lastJsonfile="/var/log/backup-last.json"
# Prefix of the summary line, matched by log-based alert rules.
readonly SUMMARY_MSG="Backup Summary"

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

# Prints restic's run summary as one logfmt line, so a log pipeline can alert
# on the share of new or changed files (ransomware rewrites them all). restic
# also writes a summary when some files could not be read (exit status 3);
# after a fatal error it writes none, and "Backup Failed" already says so.
logSummary() {
  local line
  if ! line=$(jq -r --arg msg "$SUMMARY_MSG" 'select(.message_type == "summary")
      | "msg=\"\($msg)\" files_new=\(.files_new) files_changed=\(.files_changed)"
        + " files_unmodified=\(.files_unmodified) files_total=\(.total_files_processed)"
        + " data_added=\(.data_added) bytes_total=\(.total_bytes_processed)"
        + " snapshot=\(.snapshot_id[0:8])"' "$lastJsonfile"); then
    echo "${SUMMARY_MSG} unreadable: jq failed on ${lastJsonfile}"
    return
  fi
  if [[ -n "$line" ]]; then
    echo "$line"
  elif [[ $backupRC -eq 0 ]]; then
    echo "${SUMMARY_MSG} missing: restic wrote no summary"
  fi
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

# Do not save full backup log to logfile but to backup-last.log. With --json
# --quiet, stdout carries only the summary; errors go to stderr as JSON.
restic backup --json --quiet "${backupSources[@]}" "${jobArgs[@]}" \
    --tag="${RESTIC_TAG?"Missing environment variable RESTIC_TAG"}" > "$lastJsonfile" 2>> "$lastLogfile"
backupRC=$?
cat "$lastJsonfile" >> "$lastLogfile"
logLast "Finished backup at $(date)"
logSummary
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
