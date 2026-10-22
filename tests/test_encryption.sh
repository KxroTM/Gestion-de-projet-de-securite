#!/usr/bin/env bash
# DS03 - Chiffrement : restic snapshots avec un mauvais mot de passe echoue, et le
# nom du niveau (chaine connue du monde) est introuvable en clair dans le depot restic.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ID="encryption"
REQ="DS03"
BACKUP_IMAGE="itzg/mc-backup:2026.10.1"

container_env() {
  docker inspect -f '{{ range .Config.Env }}{{ println . }}{{ end }}' "$1" | sed -n "s/^$2=//p"
}
volume_for() {
  docker inspect -f "{{ range .Mounts }}{{ if eq .Destination \"$2\" }}{{ .Name }}{{ end }}{{ end }}" "$1"
}

start=$(date +%s)
result="OK"
proof_lines=()

RESTIC_REPO_PATH="$(container_env backup RESTIC_REPOSITORY)"
RESTIC_REPO_VOL="$(volume_for backup "$RESTIC_REPO_PATH")"

LEVEL_NAME="$(docker compose exec -T mc sh -c "grep '^level-name=' /data/server.properties | cut -d= -f2" | tr -d '\r\n')"
[ -z "$LEVEL_NAME" ] && LEVEL_NAME="world"
proof_lines+=("Depot restic: $RESTIC_REPO_PATH ($RESTIC_REPO_VOL). Chaine recherchee en clair: '$LEVEL_NAME'")

# 1. Un mauvais mot de passe doit faire echouer restic snapshots.
if wrong_output="$(MSYS_NO_PATHCONV=1 docker run --rm \
    -v "$RESTIC_REPO_VOL:$RESTIC_REPO_PATH" \
    -e RESTIC_REPOSITORY="$RESTIC_REPO_PATH" \
    -e RESTIC_PASSWORD="mot-de-passe-invalide-pour-le-test" \
    --entrypoint restic "$BACKUP_IMAGE" snapshots 2>&1)"; then
  wrong_exit=0
else
  wrong_exit=$?
fi
proof_lines+=("restic snapshots avec mauvais mot de passe (exit=$wrong_exit):"$'\n'"$wrong_output")
if [ "$wrong_exit" -eq 0 ]; then
  result="FAIL"
  proof_lines+=("ECHEC: restic snapshots a reussi avec un mauvais mot de passe")
fi

# 2. Le nom du niveau ne doit apparaitre en clair dans aucun fichier du depot.
grep_matches="$(MSYS_NO_PATHCONV=1 docker run --rm \
  -v "$RESTIC_REPO_VOL:$RESTIC_REPO_PATH:ro" \
  --entrypoint sh "$BACKUP_IMAGE" -c "grep -r -l -i -- '$LEVEL_NAME' $RESTIC_REPO_PATH" || true)"
if [ -z "$grep_matches" ]; then
  proof_lines+=("Aucune occurrence en clair de '$LEVEL_NAME' dans le depot restic.")
else
  result="FAIL"
  proof_lines+=("ECHEC: '$LEVEL_NAME' trouve en clair dans: $grep_matches")
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
