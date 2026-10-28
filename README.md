# restic-backup

A sidecar container that runs [restic](https://restic.net/) backups on a cron schedule, with
pre-/post-backup hooks for database dumps. Published as
[`polandy/restic-backup`](https://hub.docker.com/r/polandy/restic-backup) for `linux/amd64` and
`linux/arm64` on every `vX.Y.Z` git tag.

Forked from [lobaro/restic-backup-docker](https://github.com/lobaro/restic-backup-docker) and trimmed
to what a homelab sidecar needs: the upstream mail, Microsoft Teams, NFS-mount and OpenStack
conveniences are gone, and every tool in the image is pinned or comes from the pinned base image.

## Contents

| Tool                | Source                                                 | Used for                              |
|---------------------|--------------------------------------------------------|---------------------------------------|
| `restic`            | base image `restic/restic` (pinned by digest)          | backups and checks                    |
| `rclone`            | `rclone/rclone` image (pinned by digest)               | `rclone:` repositories                |
| `docker-cli`        | Alpine package                                         | hooks that stop/start or exec into app containers |
| `postgresql-client` | Alpine package                                         | `pg_dump`/`pg_dumpall` in hooks       |
| `sqlite`            | Alpine package                                         | consistent online SQLite copies in hooks |
| `bash`              | Alpine package                                         | hook scripts                          |

## Environment variables

* `RESTIC_REPOSITORY` - the restic repository. Default `/mnt/restic`.
* `RESTIC_PASSWORD` - the repository password.
* `RESTIC_INIT_REPO` - `true` lets the entrypoint run `restic init` when the repository does not
  exist yet. Without it a missing repository stops the container with exit status 1.
* `RESTIC_TAG` - required by `/bin/backup`; tags every snapshot.
* `BACKUP_CRON` - cron expression for `/bin/backup` (UTC). Default `0 */6 * * *`. An empty value
  disables the scheduled backup, e.g. when the host runs `/bin/backup` via `docker exec`.
* `CHECK_CRON` - optional cron expression for `/bin/check` (`restic check`, UTC).
* `RESTIC_DATA_SUBSET` - optional `--read-data-subset` value for the check; without it only the
  repository structure is verified.
* `RESTIC_FORGET_ARGS` - optional; when set, `restic forget` runs with these arguments after every
  successful backup.
* `RESTIC_JOB_ARGS` - optional extra arguments for `restic backup` (e.g. `--exclude`).
* `RESTIC_INIT_ARGS` - optional extra arguments for `restic init`.
* `BACKUP_SOURCES` - what to back up. Default `/data`.

Backend credentials (`AWS_*`, `OS_*`, `B2_*`, ...) are read by restic itself and can be passed as
usual; the image sets no defaults for them.

## Volumes

* `/data` - the data to back up; mount the sources below it.
* `/hooks` - optional hook scripts (see below).
* `/root/.config/rclone/rclone.conf` - the rclone config for `rclone:` repositories. Mount the
  whole directory instead if a backend writes tokens back to the file.

## Hooks

`/bin/backup` runs `/hooks/pre-backup.sh` before the backup and aborts with exit status 1 if it
fails. `/hooks/post-backup.sh` runs afterwards and receives the backup's exit status as `$1`.
`/bin/check` runs `/hooks/pre-check.sh` and `/hooks/post-check.sh` the same way.

## Startup

The entrypoint opens the repository with `restic cat config`. Only when restic reports that the
repository does not exist (exit status 10) and `RESTIC_INIT_REPO=true` does it run
`restic init ${RESTIC_INIT_ARGS}`. Any other error - an unreachable backend, an expired rclone
token, a wrong password - stops the container with a message naming restic's exit status and exit
status 1, so a misconfiguration never ends in a second repository. It then writes the crontab and
starts `crond -f`.

## Logs and exit status

The cron jobs write to the container's stdout (`/proc/1/fd/1`), so `docker logs` and any log
collector see them; nothing grows inside the container. The full restic output of the last run is in
`/var/log/backup-last.log` (`/var/log/check-last.log`), and copied to
`/var/log/backup-error-last.log` (`/var/log/check-error-last.log`) when the run fails.

`/bin/backup` logs `Backup Successful` or `Backup Failed with Status <rc>` and exits with the
status of `restic backup`, else of `restic forget`, which logs `Forget Successful` or
`Forget Failed with Status <rc>`. `/bin/check` logs `Check Successful` or
`Check Failed with Status <rc>` and exits with the status of `restic check`. Alerting may match
these lines, so they are part of the interface.

`/bin/healthcheck` (also the image's `HEALTHCHECK`) exits 0 while `crond` runs, else 1. It stays
healthy with an empty `BACKUP_CRON`; failed runs show up in the lines above, not here.

## Manual use

```
docker exec -ti <container> /bin/backup
docker exec -ti <container> /bin/check
docker exec <container> sh -c '/usr/bin/flock -n /var/run/backup.lock /bin/check > /proc/1/fd/1 2>&1'  # like cron, result in docker logs
docker exec -ti <container> restic snapshots
docker exec -ti <container> restic restore <snapshot> --include /data/path --target /restore
```

restic records the container's hostname with each snapshot, so set `hostname:` to a stable value.

## Example

```yaml
services:
  restic:
    image: polandy/restic-backup:vX.Y.Z
    hostname: nas
    init: true
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "/bin/healthcheck"]
    volumes:
      - /srv/app:/data/app:ro
      - ./restic-hooks:/hooks:ro
      - ./rclone.conf:/root/.config/rclone/rclone.conf:ro
    environment:
      - RESTIC_REPOSITORY=rclone:remote:restic-app
      - RESTIC_PASSWORD=change-me
      - RESTIC_TAG=app
      - RESTIC_INIT_REPO=true
      - BACKUP_CRON=0 3 * * *
      - CHECK_CRON=0 12 1 * *
      - RESTIC_DATA_SUBSET=2G
      - RESTIC_FORGET_ARGS=--prune --keep-daily 7 --keep-monthly 12
```

## Versioning

[Semantic versioning](https://semver.org/); changes are listed in [`CHANGELOG.md`](CHANGELOG.md).
