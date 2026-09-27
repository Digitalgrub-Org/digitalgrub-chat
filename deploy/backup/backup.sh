#!/bin/sh
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGDATABASE:?PGDATABASE is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"

interval="${BACKUP_INTERVAL_SECONDS:-86400}"
retention="${BACKUP_RETENTION_DAYS:-14}"

case "$interval" in
  ''|*[!0-9]*) echo "BACKUP_INTERVAL_SECONDS must be an integer" >&2; exit 1 ;;
esac
case "$retention" in
  ''|*[!0-9]*) echo "BACKUP_RETENTION_DAYS must be an integer" >&2; exit 1 ;;
esac

mkdir -p /backups

while true; do
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  destination="/backups/${PGDATABASE}_${timestamp}.dump"
  temporary="${destination}.tmp"

  pg_dump --format=custom --compress=9 --file="$temporary"
  mv "$temporary" "$destination"
  find /backups -type f -name "${PGDATABASE}_*.dump" -mtime "+${retention}" -delete
  touch /tmp/backup-healthy
  echo "Created PostgreSQL backup ${destination}"

  sleep "$interval" &
  wait $!
done
