#!/bin/bash
# check-backup.sh - Verifie la fraicheur de la derniere sauvegarde reussie
# Usage : check-backup.sh [age_max_en_minutes]   (defaut : 1500 = 25 h)
# Codes de retour : 0 = OK, 1 = sauvegarde trop ancienne,
#                   2 = aucune sauvegarde reussie, 3 = date illisible

LOG="/var/log/backup/backup.log"
MAX_AGE_MIN="${1:-1500}"

# Derniere ligne "BACKUP OK", puis extraction de la date au format AAAA-MM-JJ HH:MM:SS
line=$(grep "BACKUP OK" "$LOG" 2>/dev/null | tail -n 1)
last=$(echo "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}')

if [ -z "$last" ]; then
    echo "ALERTE : aucune sauvegarde reussie trouvee dans le log"
    exit 2
fi

# Conversion de la date en secondes, avec verification
last_ts=$(date -d "$last" +%s 2>/dev/null)
if [ -z "$last_ts" ]; then
    echo "ERREUR : date illisible dans le log : '$last'"
    exit 3
fi

age=$(( ( $(date +%s) - last_ts ) / 60 ))

if [ "$age" -gt "$MAX_AGE_MIN" ]; then
    echo "ALERTE : derniere sauvegarde reussie il y a $age min ($last)"
    exit 1
fi

echo "OK : derniere sauvegarde reussie il y a $age min ($last)"
exit 0