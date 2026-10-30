#!/usr/bin/env bash
# Runs every test against the given image and reports each one, so a run
# against an older build shows exactly which behaviour it lacks.
#   tests/run.sh <image>
set -u -o pipefail

readonly IMAGE="${1:?usage: tests/run.sh <image>}"
readonly RUN_ID="restic-test-$$"
readonly WORK_DIR="$(mktemp -d)"
readonly RESTIC_EXIT_WRONG_PASSWORD=12

volumes=()
failed=()

cleanup() {
    if [[ ${#volumes[@]} -gt 0 ]]; then
        docker volume rm "${volumes[@]}" > /dev/null
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# A fresh, empty named volume for a repository under /repo.
new_volume() {
    local name="${RUN_ID}-$1"
    docker volume create "$name" > /dev/null
    volumes+=("$name")
    echo "$name"
}

# docker run with the variables every test needs; extra args before the image.
run() {
    docker run --rm -e RESTIC_PASSWORD=smoke -e RESTIC_TAG=smoke "$@"
}

# Sets $out and $rc from a command.
capture() {
    out="$("$@" 2>&1)"
    rc=$?
}

expect_rc() {
    if [[ $rc -ne $1 ]]; then
        echo "  expected exit status $1, got $rc"
        echo "$out" | sed 's/^/  | /'
        return 1
    fi
}

expect_nonzero_rc() {
    if [[ $rc -eq 0 ]]; then
        echo "  expected a non-zero exit status, got 0"
        echo "$out" | sed 's/^/  | /'
        return 1
    fi
}

expect_out() {
    if ! grep -qF -- "$1" <<< "$out"; then
        echo "  expected output containing: $1"
        echo "$out" | sed 's/^/  | /'
        return 1
    fi
}

test_tools() {
    capture run --entrypoint sh "$IMAGE" -c \
        'restic version && rclone version && sqlite3 --version && pg_dumpall --version && bash --version'
    expect_rc 0 || return 1
    # The removed, unpinned tools must stay out of the image.
    local tool
    for tool in calcardbackup mail curl docker; do
        capture run --entrypoint sh "$IMAGE" -c "command -v $tool || echo ABSENT"
        expect_out ABSENT || return 1
    done
}

test_missing_repo_init() {
    local vol
    vol=$(new_volume init)
    capture run -v "$vol:/repo" -e RESTIC_REPOSITORY=/repo/r -e RESTIC_INIT_REPO=true "$IMAGE" restic cat config
    expect_rc 0
}

test_missing_repo_without_init() {
    local vol
    vol=$(new_volume noinit)
    capture run -v "$vol:/repo" -e RESTIC_REPOSITORY=/repo/r "$IMAGE" echo CMD_REACHED
    expect_rc 1 || return 1
    expect_out "does not exist and RESTIC_INIT_REPO is not true" || return 1
    # The repository volume must still be empty: an empty listing, positively read.
    capture run -v "$vol:/repo" --entrypoint sh "$IMAGE" -c 'echo "entries=$(ls -A /repo | wc -l)"'
    expect_out "entries=0"
}

test_wrong_password() {
    local vol
    vol=$(new_volume wrongpw)
    capture run -v "$vol:/repo" -e RESTIC_REPOSITORY=/repo/r --entrypoint restic "$IMAGE" init
    expect_rc 0 || return 1
    capture docker run --rm -v "$vol:/repo" -e RESTIC_REPOSITORY=/repo/r -e RESTIC_PASSWORD=wrong \
        -e RESTIC_INIT_REPO=true "$IMAGE" echo CMD_REACHED
    expect_rc 1 || return 1
    expect_out "(restic exit ${RESTIC_EXIT_WRONG_PASSWORD})"
}

test_check_status() {
    capture run -e RESTIC_REPOSITORY=/tmp/repo --entrypoint sh "$IMAGE" -c 'restic init -q && /bin/check'
    expect_rc 0 || return 1
    expect_out "Check Successful" || return 1
    capture run -e RESTIC_REPOSITORY=/tmp/repo --entrypoint /bin/check "$IMAGE"
    expect_nonzero_rc || return 1
    expect_out "Check Failed with Status"
}

test_pre_check_failure() {
    mkdir -p "$WORK_DIR/hooks"
    printf '#!/bin/sh\nexit 1\n' > "$WORK_DIR/hooks/pre-check.sh"
    chmod 755 "$WORK_DIR/hooks" "$WORK_DIR/hooks/pre-check.sh"
    capture run -v "$WORK_DIR/hooks:/hooks:ro" -e RESTIC_REPOSITORY=/tmp/repo --entrypoint sh "$IMAGE" \
        -c 'restic init -q && /bin/check'
    expect_rc 1 || return 1
    expect_out "pre-check script failed"
}

test_backup_status() {
    capture run -e RESTIC_REPOSITORY=/tmp/repo --entrypoint sh "$IMAGE" -c 'restic init -q && /bin/backup'
    expect_rc 0 || return 1
    capture run -e RESTIC_REPOSITORY=/tmp/repo --entrypoint /bin/backup "$IMAGE"
    expect_nonzero_rc
}

# The entrypoint prints the crontab it wrote: the default must schedule the
# backup, an empty BACKUP_CRON must not, and CHECK_CRON must work either way.
test_backup_cron() {
    local crontab=(sed 's/^/CRON: /' /var/spool/cron/crontabs/root)
    capture run -e RESTIC_REPOSITORY=/tmp/repo -e RESTIC_INIT_REPO=true "$IMAGE" "${crontab[@]}"
    expect_out "CRON: 0 */6 * * * " || return 1
    capture run -e RESTIC_REPOSITORY=/tmp/repo -e RESTIC_INIT_REPO=true -e BACKUP_CRON= \
        -e "CHECK_CRON=0 12 9 * *" "$IMAGE" "${crontab[@]}"
    expect_out "BACKUP_CRON is empty, no backup cron job set up" || return 1
    expect_out "CRON: 0 12 9 * * " || return 1
    if grep -q '^CRON: .*/bin/backup' <<< "$out"; then
        echo "  an empty BACKUP_CRON still scheduled /bin/backup"
        return 1
    fi
}

# Runs the backup job exactly as cron would, under tini like the sidecars: its
# result lines must reach the container's stdout, where Loki reads them.
test_job_logs_to_stdout() {
    capture run --init -e RESTIC_REPOSITORY=/tmp/repo -e RESTIC_INIT_REPO=true "$IMAGE" \
        bash -c 'eval "$(grep /bin/backup /var/spool/cron/crontabs/root | cut -d" " -f6-)"'
    expect_rc 0 || return 1
    expect_out "Backup Successful" || return 1
    capture docker image inspect --format '{{json .Config.Cmd}}' "$IMAGE"
    expect_out '["crond","-f"]' || return 1
    capture run --entrypoint sh "$IMAGE" -c '[ -e /var/log/cron.log ] && echo PRESENT || echo ABSENT'
    expect_out ABSENT
}

# Healthy with crond running (also with an empty crontab), unhealthy without:
# exactly 1, so a missing /bin/healthcheck (127) does not count as unhealthy.
test_healthcheck() {
    capture run -e BACKUP_CRON= --entrypoint sh "$IMAGE" -c ': > /var/spool/cron/crontabs/root && crond && /bin/healthcheck'
    expect_rc 0 || return 1
    capture run --entrypoint /bin/healthcheck "$IMAGE"
    expect_rc 1
}

for t in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do
    if "$t"; then
        echo "PASS $t"
    else
        echo "FAIL $t"
        failed+=("$t")
    fi
done

if [[ ${#failed[@]} -gt 0 ]]; then
    echo "${#failed[@]} test(s) failed: ${failed[*]}"
    exit 1
fi
echo "All tests passed"
