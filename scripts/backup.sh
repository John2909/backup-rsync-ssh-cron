#!/bin/bash
# backup.sh - Sauvegarde de /srv/data vers srv-backup avec rsync + SSH

set -uo pipefail

SRC="/srv/data/"
DEST="backupuser@192.168.100.114:/backup/data/"
LOG="/var/log/backup/backup.log"
LOCK="/tmp/backup.lock"

# Empêche deux sauvegardes de tourner en même temps
exec 9>"$LOCK"
if ! flock -n 9; then
    echo "$(date '+%F %T') Sauvegarde deja en cours, abandon" >> "$LOG"
    exit 1
fi

echo "===== BACKUP START $(date '+%F %T') =====" >> "$LOG"

/usr/bin/rsync -az --stats -e "ssh -o BatchMode=yes -o ConnectTimeout=10" "$SRC" "$DEST" >> "$LOG" 2>&1
STATUS=$?

if [ $STATUS -eq 0 ]; then
    echo "===== BACKUP OK $(date '+%F %T') =====" >> "$LOG"
else
    echo "===== BACKUP ECHEC (code $STATUS) $(date '+%F %T') =====" >> "$LOG"
fi

exit $STATUS