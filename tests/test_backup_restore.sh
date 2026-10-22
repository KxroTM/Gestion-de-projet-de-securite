#!/usr/bin/env bash
# E08 / DS07 - Sauvegarde et restauration restic : l'empreinte du monde est identique
# avant/apres restauration, la restauration prend moins de 900s, et le bloc temoin
# place par RCON est bien present apres redemarrage.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ID="backup_restore"
REQ="E08 / DS07"
RESTORE_THRESHOLD_S="${RESTORE_THRESHOLD_S:-900}"
MC_IMAGE="itzg/minecraft-server:2026.10.0-java25"
BACKUP_IMAGE="itzg/mc-backup:2026.10.1"

container_env() {
  # container_env <container> <VAR_NAME>
  docker inspect -f '{{ range .Config.Env }}{{ println . }}{{ end }}' "$1" | sed -n "s/^$2=//p"
}

volume_for() {
  # volume_for <container> <destination>
  docker inspect -f "{{ range .Mounts }}{{ if eq .Destination \"$2\" }}{{ .Name }}{{ end }}{{ end }}" "$1"
}

hash_world() {
  # hash_world : SHA-256 agrege du dossier /data/world (fichiers tries) via conteneur jetable
  docker run --rm -v "$MC_DATA_VOL:/data:ro" --entrypoint sh "$MC_IMAGE" -c \
    "find /data/world -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum" | awk '{print $1}'
}

start=$(date +%s)
result="OK"
proof_lines=()

MC_DATA_VOL="$(volume_for mc /data)"
RESTIC_REPO_PATH="$(container_env backup RESTIC_REPOSITORY)"
RESTIC_REPO_VOL="$(volume_for backup "$RESTIC_REPO_PATH")"
RESTIC_PASSWORD_VAL="$(container_env backup RESTIC_PASSWORD)"
proof_lines+=("Volume monde: $MC_DATA_VOL, depot restic: $RESTIC_REPO_PATH ($RESTIC_REPO_VOL)")

# 1. Bloc temoin + flush (save-off d'abord pour geler le monde sur disque)
rcon forceload add 0 0 >/dev/null
rcon "setblock 0 100 0 minecraft:diamond_block" >/dev/null
rcon save-off >/dev/null
rcon "save-all flush" >/dev/null
proof_lines+=("Bloc temoin place en 0,100,0 et monde fige (save-off + save-all flush).")

# 2. Sauvegarde du monde fige
backup_output="$(docker compose exec -T backup backup now 2>&1)"
proof_lines+=("backup now:"$'\n'"$backup_output")

# 3. Empreinte AVANT, calculee pendant que le serveur tourne encore (autosave coupe,
#    donc le disque ne bouge plus) pour qu'elle corresponde exactement a ce qui a ete
#    sauvegarde. On tue ensuite le serveur sans grace (SIGKILL) pour eviter qu'un arret
#    propre ne redeclenche une sauvegarde et ne desynchronise le disque du snapshot.
hash_before="$(hash_world)"
docker kill mc >/dev/null
proof_lines+=("Empreinte avant restauration: $hash_before")

# 4. Suppression du monde
docker run --rm -v "$MC_DATA_VOL:/data" --entrypoint sh "$MC_IMAGE" -c "rm -rf /data/world" >/dev/null
proof_lines+=("Dossier world supprime.")

# 5. Restauration chronometree
restore_start=$(date +%s)
restore_output="$(MSYS_NO_PATHCONV=1 docker run --rm \
  -v "$MC_DATA_VOL:/data" \
  -v "$RESTIC_REPO_VOL:$RESTIC_REPO_PATH" \
  -e RESTIC_REPOSITORY="$RESTIC_REPO_PATH" \
  -e RESTIC_PASSWORD="$RESTIC_PASSWORD_VAL" \
  --entrypoint restic "$BACKUP_IMAGE" restore latest --target / 2>&1)"
restore_end=$(date +%s)
restore_duration=$((restore_end - restore_start))
proof_lines+=("restic restore latest (${restore_duration}s):"$'\n'"$restore_output")

if [ "$restore_duration" -gt "$RESTORE_THRESHOLD_S" ]; then
  result="FAIL"
  proof_lines+=("ECHEC: restauration (${restore_duration}s) > seuil (${RESTORE_THRESHOLD_S}s)")
fi

# 6. Empreinte APRES
hash_after="$(hash_world)"
proof_lines+=("Empreinte apres restauration: $hash_after")

if [ "$hash_before" != "$hash_after" ]; then
  result="FAIL"
  proof_lines+=("ECHEC: empreintes differentes ($hash_before != $hash_after)")
fi

# 7. Redemarrage de mc et verification RCON du bloc temoin
docker compose start mc >/dev/null
if wait_healthy mc 180; then
  proof_lines+=("mc de nouveau healthy en ${WAIT_HEALTHY_SECONDS}s")
else
  result="FAIL"
  proof_lines+=("ECHEC: mc n'est pas redevenu healthy apres restauration")
fi

rcon forceload add 0 0 >/dev/null
block_check="$(rcon "execute if block 0 100 0 minecraft:diamond_block run seed")"
proof_lines+=("Verification RCON du bloc temoin: '$block_check'")
if ! echo "$block_check" | grep -q "Seed:"; then
  result="FAIL"
  proof_lines+=("ECHEC: bloc temoin absent apres restauration")
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
