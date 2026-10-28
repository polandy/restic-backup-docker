#!/bin/sh

lastLogfile="/var/log/check-last.log"

copyErrorLog() {
  cp ${lastLogfile} /var/log/check-error-last.log
}

logLast() {
  echo "$1" >> ${lastLogfile}
}

if [ -f "/hooks/pre-check.sh" ]; then
    echo "Starting pre-check script ..."
    /hooks/pre-check.sh
else
    echo "Pre-check script not found ..."
fi

start=`date +%s`
rm -f ${lastLogfile}
echo "Starting Check at $(date +"%Y-%m-%d %H:%M:%S")"
echo "Starting Check at $(date)" >> ${lastLogfile}
logLast "CHECK_CRON: ${CHECK_CRON}"
logLast "RESTIC_DATA_SUBSET: ${RESTIC_DATA_SUBSET}"
logLast "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"

# Do not save full check log to logfile but to check-last.log
if [ -n "${RESTIC_DATA_SUBSET}" ]; then
    restic check --read-data-subset=${RESTIC_DATA_SUBSET} >> ${lastLogfile} 2>&1
else
    restic check >> ${lastLogfile} 2>&1
fi
checkRC=$?
logLast "Finished check at $(date)"
if [[ $checkRC == 0 ]]; then
    echo "Check Successful"
else
    echo "Check Failed with Status ${checkRC}"
    restic unlock
    copyErrorLog
fi

end=`date +%s`
echo "Finished Check at $(date +"%Y-%m-%d %H:%M:%S") after $((end-start)) seconds"

if [ -f "/hooks/post-check.sh" ]; then
    echo "Starting post-check script ..."
    /hooks/post-check.sh $checkRC
else
    echo "Post-check script not found ..."
fi
