#!/usr/bin/env bash
# E08 / DS01 - Le planificateur de sauvegardes automatiques fonctionne reellement
# (pas seulement le declenchement manuel "backup now") : avec un intervalle reduit
# le temps du test, plusieurs sauvegardes automatiques doivent apparaitre toutes
# seules, a intervalle regulier. Prouve que la planification marche sans attendre
# 24h (DS01 parle de sauvegardes horaires sur 24h ; on verifie le mecanisme a une
# echelle de temps compatible avec la CI).
#
# On compte les sauvegardes dans les LOGS du conteneur (lignes "snapshot ... saved"),
# pas dans le nombre de snapshots restants : PRUNE_RESTIC_RETENTION (--keep-hourly)
# elague automatiquement les sauvegardes d'une meme heure apres coup, donc compter
# les snapshots survivants sous-estimerait la frequence reelle des sauvegardes.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ID="backup_frequency"
REQ="E08 / DS01"
TEST_INTERVAL="${BACKUP_FREQ_TEST_INTERVAL:-1m}"
WAIT_SECONDS="${BACKUP_FREQ_WAIT_S:-300}"
MIN_BACKUPS="${BACKUP_FREQ_MIN_BACKUPS:-4}"

OVERRIDE_FILE="$(mktemp -t backup-freq-override-XXXXXX.yml)"
trap 'rm -f "$OVERRIDE_FILE"; docker compose -f docker-compose.yml -f docker-compose.ci.yml up -d --no-deps --force-recreate backup >/dev/null 2>&1 || true' EXIT

cat > "$OVERRIDE_FILE" <<EOF
services:
  backup:
    environment:
      BACKUP_INTERVAL: "$TEST_INTERVAL"
      INITIAL_DELAY: "5"
      BACKUP_ON_STARTUP: "true"
EOF

start=$(date +%s)
result="OK"
proof_lines=()

docker compose -f docker-compose.yml -f docker-compose.ci.yml -f "$OVERRIDE_FILE" \
  up -d --no-deps --force-recreate backup >/dev/null
test_start_iso="$(date -u +%Y-%m-%dT%H:%M:%S)"
proof_lines+=("Service backup recree a ${test_start_iso}Z avec BACKUP_INTERVAL=$TEST_INTERVAL, INITIAL_DELAY=5s.")

echo "Attente de ${WAIT_SECONDS}s pour laisser le planificateur tourner..."
sleep "$WAIT_SECONDS"

logs="$(docker compose logs backup --no-log-prefix --since "$test_start_iso" 2>&1)"
save_lines="$(echo "$logs" | grep -E "snapshot [a-f0-9]+ saved" || true)"
backup_count="$(echo "$save_lines" | grep -c . || true)"
proof_lines+=("Sauvegardes automatiques executees en ${WAIT_SECONDS}s (attendu >= $MIN_BACKUPS):"$'\n'"$save_lines")
proof_lines+=("Total: $backup_count")

if [ "$backup_count" -lt "$MIN_BACKUPS" ]; then
  result="FAIL"
  proof_lines+=("ECHEC: seulement $backup_count sauvegarde(s) automatique(s) en ${WAIT_SECONDS}s")
fi

end=$(date +%s)
duration=$((end - start))
proof="$(printf '%s\n' "${proof_lines[@]}")"
echo "$proof"

write_report "$ID" "$REQ" "$result" "$duration" "$proof"

if [ "$result" != "OK" ]; then
  echo "TEST $ID FAILED" >&2
  exit 1
fi
echo "TEST $ID OK"
