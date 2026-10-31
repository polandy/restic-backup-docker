# Changelog

## v3.1.0
### Added
* `/bin/sqlite-backup <database> <dump-dir> [--require-shm]`: consistent, integrity-checked copy of a live SQLite database for pre-backup hooks; a failed run keeps the previous copy

## v3.0.0
### Removed
* **Breaking:** `docker-cli`; hooks can no longer stop, start or exec into other containers from the sidecar. Run such steps on the host and call `/bin/backup` via `docker exec` (with `BACKUP_CRON=""`)

## v2.0.0
### Added
* `RESTIC_INIT_REPO=true` lets the entrypoint run `restic init` when the repository does not exist
* `/bin/healthcheck`, also the image's `HEALTHCHECK`: healthy while `crond` runs
### Changed
* **Breaking:** the entrypoint initialises a repository only when `restic cat config` reports it missing (exit 10) and `RESTIC_INIT_REPO=true`; any other error (network, rclone token, password) stops the container with a message and exit status 1 instead of running `restic init`
* **Breaking:** cron jobs log to the container's stdout (`docker logs`); `/var/log/cron.log` and the `tail -f` CMD are gone, the CMD is `crond -f`
* **Breaking:** `/bin/check` exits with the status of `restic check` and aborts with exit status 1 when `/hooks/pre-check.sh` fails
* The scripts run under bash with `set -u`, and the argument variables are split into arguments without glob expansion
* rclone comes from the `rclone/rclone:1.75.2` image and both base images are pinned by digest, instead of `alpine:latest` plus `rclone-current`
### Removed
* `calcardbackup`, downloaded unpinned from a branch at build time
* `MAILX_ARGS` and `TEAMS_WEBHOOK_URL` notifications, with `mailx` and `curl`
* `NFS_TARGET` mounting, with `fuse`
* The image defaults for the OpenStack `OS_*` variables (restic still reads them when set)
* `shadow` and the OpenShift group-permission fix
* `AWS_ACCESS_KEY_ID` in `backup-last.log` and `check-last.log`
* `build.sh`, `run.sh` and the broken container-structure-test files; CI covers the build

## v1.6.0
### Added
* An empty `BACKUP_CRON` disables the scheduled backup, for hosts that run `/bin/backup` themselves
### Changed
* `/bin/backup` exits with the status of `restic backup`, else of `restic forget`, instead of always 0

## v1.5.0
### Added
* `sqlite3` for consistent online copies of SQLite databases in backup hooks
### Changed
* CI publishes to Docker Hub (`polandy/restic-backup`) on `vX.Y.Z` tags for linux/amd64 and linux/arm64; pull requests build only
### Removed
* The `latest`-pushing legacy workflow and the ghcr.io publish target
* linux/arm/v7 build

## v1.4.2
### Removed 
* Execute a repository check after prune was passed as a parameter in the forget call - use RESTIC_CHECK_CRON Var instead

## v1.4.1
### Changed
* Execute a repository check after prune was passed as a parameter in the forget call

## v1.4.0

### Added
* Option to set the target folder backup
* Multi-platform image build

## v1.3.2 (restic 0.16.0)

### Changed
* Base image directly on official restic image
* [Semver](https://semver.org/) aligned version naming including restic version
* Updated to restic 0.16.0

### Added
* rclone to docker image
* Implemented a simple mail notification after backups using mailx
* MAILX_ARGS environment variable

## v1.3.1-0.9.6

### Changed
* Update to Restic v0.9.5
* Reduced the number of layers in the Docker image

### Fixed
* Check if a repo already exists works now for all repository types

### Added
* shh added to container
* fuse added to container
* support to send mails using external SMTP server after backups

## v1.2-0.9.4

### Added
* AWS Support

## v1.1

### Fixed
* `--prune` must be passed to `RESTIC_FORGET_ARGS` to execute prune after forget.

### Changed
* Switch to base Docker container to `golang:1.7-alpine` to support latest restic build.

## v1.0

Initial release.

The container has proper logs now and was running for over a month in production. 
There are still some features missing. Sticking to semantic versioning we do not expect any breaking changes in the 1.x releases.
