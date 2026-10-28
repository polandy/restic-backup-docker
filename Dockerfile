# Both images pinned by version and digest so a rebuild of the same commit
# yields the same binaries; Dependabot bumps them.
FROM docker.io/rclone/rclone:1.75.2@sha256:2687085f718d3c628f7fdfb77c52a1d344332aed543110bb88088f2c70d43eb5 AS rclone

FROM docker.io/restic/restic:0.18.0@sha256:4cf4a61ef9786f4de53e9de8c8f5c040f33830eb0a10bf3d614410ee2fcb6120

# Tools the pre-/post-backup hooks run inside the sidecar: database dumps
# (postgresql-client, sqlite) and controlling app containers (docker-cli).
RUN apk add --no-cache \
      bash \
      docker-cli \
      postgresql-client \
      sqlite

COPY --from=rclone /usr/local/bin/rclone /bin/rclone

RUN mkdir -p /mnt/restic /var/spool/cron/crontabs /var/log

ENV RESTIC_REPOSITORY=/mnt/restic
ENV RESTIC_PASSWORD=""
ENV RESTIC_TAG=""
ENV BACKUP_CRON="0 */6 * * *"
ENV CHECK_CRON=""
ENV RESTIC_INIT_REPO=""
ENV RESTIC_INIT_ARGS=""
ENV RESTIC_FORGET_ARGS=""
ENV RESTIC_JOB_ARGS=""
ENV RESTIC_DATA_SUBSET=""
ENV BACKUP_SOURCES=""

# /data is the dir where you have to put the data to be backed up
VOLUME /data

COPY backup.sh /bin/backup
COPY check.sh /bin/check
COPY healthcheck.sh /bin/healthcheck
COPY entry.sh /entry.sh

HEALTHCHECK CMD ["/bin/healthcheck"]

# crond in the foreground keeps the container alive; the jobs log to the
# container's stdout themselves (see entry.sh).
ENTRYPOINT ["/entry.sh"]
CMD ["crond", "-f"]
