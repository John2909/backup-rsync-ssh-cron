#!/bin/bash
# restore.sh - Restaure /srv/data depuis srv-backup
# Usage : restore.sh --dry-run   (simulation)
#         restore.sh             (restauration reelle)

set -uo pipefail

SRC="backupuser@192.168.100.114:/backup/data/"
DEST="/srv/data/"

if [ "${1:-}" = "--dry-run" ]; then
    echo "Simulation (aucun fichier ne sera modifie) :"
    /usr/bin/rsync -avun "$SRC" "$DEST"
else
    echo "Restauration en cours..."
    /usr/bin/rsync -avu "$SRC" "$DEST"
    STATUS=$?
    if [ $STATUS -eq 0 ]; then
        echo "Restauration terminee avec succes."
    else
        echo "ECHEC de la restauration (code $STATUS)."
    fi
    exit $STATUS
fi