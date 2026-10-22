#!/usr/bin/env bash
# E09 - Apres un crash du serveur, le conteneur mc redevient "healthy" en moins de 180s.
#
# On simule le crash en tuant le process java DANS le conteneur (`pkill -9 java`),
# pas en faisant un `docker kill mc` sur le conteneur lui-meme : Docker traite un
# `docker kill`/`docker stop` explicite comme un arret volontaire et desactive alors
# la restart policy (`unless-stopped` ne redemarre jamais dans ce cas, c'est le
# comportement documente). Un crash interne (le process surveille par le conteneur
# meurt tout seul, PID 1 sort en erreur) est le seul declencheur realiste de
# `restart: unless-stopped`, et c'est aussi plus representatif d'un vrai crash
# serveur que la commande kill elle-meme.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ID="restart"
REQ="E09"
THRESHOLD_S="${RESTART_THRESHOLD_S:-180}"

start=$(date +%s)
docker compose exec -T mc sh -c 'pkill -9 java' >/dev/null
echo "Process java tue dans le conteneur mc (crash simule), attente du retour a l'etat healthy (seuil ${THRESHOLD_S}s)..."

result="OK"
if wait_restarted_and_healthy mc "$THRESHOLD_S"; then
  duration=$WAIT_HEALTHY_SECONDS
else
  duration=$WAIT_HEALTHY_SECONDS
  result="FAIL"
fi

end=$(date +%s)
wall_duration=$((end - start))
proof="Crash simule (pkill -9 java dans mc) a $(date -u -d "@$start" +%H:%M:%S 2>/dev/null || date -u -r "$start" +%H:%M:%S). Retour healthy en ${duration}s (seuil ${THRESHOLD_S}s). Duree totale mesuree: ${wall_duration}s."
echo "$proof"

write_report "$ID" "$REQ" "$result" "$duration" "$proof"

if [ "$result" != "OK" ]; then
  echo "TEST $ID FAILED" >&2
  exit 1
fi
echo "TEST $ID OK"
