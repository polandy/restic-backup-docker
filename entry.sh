#!/bin/bash
set -u

echo "Starting container ..."

# restic >= 0.17 exits with this status when the repository does not exist.
readonly RESTIC_EXIT_REPO_MISSING=10
# Job output goes to the stdout of PID 1 (tini with `init: true`, else crond),
# which is the container log.
readonly JOB_LOG=/proc/1/fd/1
readonly CRONTAB=/var/spool/cron/crontabs/root

# Only a repository that provably does not exist is initialised; a network,
# rclone-token or password error must not end in `restic init`.
restic cat config &> /dev/null
status=$?
if [[ $status -eq $RESTIC_EXIT_REPO_MISSING ]]; then
    if [[ "${RESTIC_INIT_REPO:-}" != "true" ]]; then
        echo "Restic repository '${RESTIC_REPOSITORY}' does not exist and RESTIC_INIT_REPO is not true. Exit 1"
        exit 1
    fi
    echo "Restic repository '${RESTIC_REPOSITORY}' does not exist. Running restic init."
    read -r -a initArgs <<< "${RESTIC_INIT_ARGS:-}"
    if ! restic init "${initArgs[@]}"; then
        echo "Failed to init the repository: '${RESTIC_REPOSITORY}'. Exit 1"
        exit 1
    fi
elif [[ $status -ne 0 ]]; then
    echo "Cannot open restic repository '${RESTIC_REPOSITORY}' (restic exit ${status}): check the network, the rclone config and the password. Exit 1"
    exit 1
fi

# Start from an empty crontab: both jobs below are appended, and a restarted
# container keeps its filesystem, so they would pile up on every start.
: > "$CRONTAB"

# An empty BACKUP_CRON leaves scheduling to the host, which then runs
# /bin/backup itself (e.g. via docker exec after a pre-backup step).
if [[ -n "${BACKUP_CRON:-}" ]]; then
    echo "Setup backup cron job with cron expression BACKUP_CRON: ${BACKUP_CRON}"
    echo "${BACKUP_CRON} /usr/bin/flock -n /var/run/backup.lock /bin/backup > ${JOB_LOG} 2>&1" >> "$CRONTAB"
else
    echo "BACKUP_CRON is empty, no backup cron job set up"
fi

# If CHECK_CRON is set we will enable automatic backup checking
if [[ -n "${CHECK_CRON:-}" ]]; then
    echo "Setup check cron job with cron expression CHECK_CRON: ${CHECK_CRON}"
    echo "${CHECK_CRON} /usr/bin/flock -n /var/run/backup.lock /bin/check > ${JOB_LOG} 2>&1" >> "$CRONTAB"
fi

echo "Container started."

exec "$@"
