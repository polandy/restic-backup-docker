# Both images pinned by version and digest so a rebuild of the same commit
# yields the same binaries; Dependabot bumps them.
FROM docker.io/rclone/rclone:1.75.2@sha256:2687085f718d3c628f7fdfb77c52a1d344332aed543110bb88088f2c70d43eb5 AS rclone

FROM docker.io/restic/restic:0.19.1@sha256:136600b6ff6843d61d355f7f71f460a166429f35de6fd11b568fece3c9a4d510

# Tools the pre-/post-backup hooks run inside the sidecar: database dumps
# (postgresql-client, sqlite). jq turns restic's JSON summary into a log line. No docker-cli: a hook that needs another
# container runs on the host, which then calls /bin/backup via docker exec.
# apk upgrade pulls Alpine's security fixes into the base's packages (openssl,
# openssh-client) on every build, not only when upstream republishes restic.
RUN apk upgrade --no-cache && apk add --no-cache \
      bash \
      jq \
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
COPY sqlite-backup.sh /bin/sqlite-backup
COPY entry.sh /entry.sh

HEALTHCHECK CMD ["/bin/healthcheck"]

# crond in the foreground keeps the container alive; the jobs log to the
# container's stdout themselves (see entry.sh).
ENTRYPOINT ["/entry.sh"]
CMD ["crond", "-f"]
