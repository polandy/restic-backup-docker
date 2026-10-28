#!/bin/bash
set -u

# Healthy while crond runs: it schedules the jobs, and it keeps running with an
# empty crontab, so an empty BACKUP_CRON still reports healthy. Failed or
# missing backup runs are reported through their log lines, not here.
if ! pgrep -x crond > /dev/null; then
    echo "crond is not running"
    exit 1
fi
