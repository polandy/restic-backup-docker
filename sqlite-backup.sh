#!/bin/bash
# Copies a live SQLite database into a directory restic backs up, for use in
# /hooks/pre-backup.sh:
#   /bin/sqlite-backup <database> <dump-dir> [--require-shm]
# The copy keeps the database's file name. Any failure exits 1 with a message,
# so /bin/backup aborts the run instead of saving a backup without the copy.
set -u

readonly USAGE="usage: sqlite-backup <database> <dump-dir> [--require-shm]"
# How long .backup waits out a running write instead of failing on the lock.
readonly BUSY_TIMEOUT_MS=30000

fail() {
  echo "sqlite-backup: $*" >&2
  exit 1
}

if [[ $# -lt 2 || $# -gt 3 || ( $# -eq 3 && "$3" != "--require-shm" ) ]]; then
  echo "$USAGE" >&2
  exit 2
fi
db=$1
dumpDir=$2
requireShm=${3:+true}
dumpFile="$dumpDir/$(basename "$db")"

# The path ends up inside a quoted sqlite3 dot-command.
[[ "$dumpFile" != *"'"* ]] || fail "dump path $dumpFile must not contain a single quote"
[[ -f "$db" ]] || fail "database $db not found"
# The hook runs as root. Without a -shm file sqlite3 would create the -wal/-shm
# pair as root, and if the copy were killed before it removed them again, an
# app running as another user could no longer open its database. They exist
# whenever the app has the database open.
if [[ -n "$requireShm" && ! -f "$db-shm" ]]; then
  fail "$db-shm missing (is the app running?); not creating it as root"
fi
mkdir -p "$dumpDir" || fail "cannot create $dumpDir"
trap 'rm -f "$dumpFile.partial"' EXIT
rm -f "$dumpFile.partial"

echo "Copying SQLite database $db..."
# The online backup API reads the database and its WAL as one snapshot while
# the app keeps writing, which restic reading the files one by one cannot.
sqlite3 -bail -cmd ".timeout $BUSY_TIMEOUT_MS" "$db" ".backup '$dumpFile.partial'" \
  || fail "sqlite3 .backup of $db failed"

# Write beside the previous copy and only replace it once verified, so a failed
# run leaves the last good copy in place rather than no copy at all.
check=$(sqlite3 "$dumpFile.partial" 'PRAGMA integrity_check;') \
  || fail "integrity check of the copy could not run"
[[ "$check" == "ok" ]] || fail "integrity check of the copy failed: $check"
mv "$dumpFile.partial" "$dumpFile" || fail "cannot move the copy to $dumpFile"

echo "SQLite copy created: $dumpFile ($(stat -c %s "$dumpFile") bytes)"
