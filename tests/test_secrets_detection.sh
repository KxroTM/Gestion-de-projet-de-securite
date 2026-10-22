#!/usr/bin/env bash
# DS05 - Un secret connu injecte dans un dossier de test doit faire echouer gitleaks.
# Controle actif qui prouve que la detection fonctionne reellement, plutot que de se
# contenter de constater que l'historique reel est (pour l'instant) propre : c'est
# la meme logique "peut echouer" que les autres tests, appliquee a gitleaks lui-meme.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ID="secrets_detection"
REQ="DS05"
GITLEAKS_IMAGE="zricethezav/gitleaks:v8.30.1"

start=$(date +%s)
result="OK"
proof_lines=()

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Faux token GitHub (regle "github-pat" de gitleaks), genere a l'execution : il ne
# doit JAMAIS etre une chaine codee en dur dans ce script, sinon le scan gitleaks
# du vrai historique du depot (job "secrets") le detecterait lui-meme comme une
# fuite reelle a chaque run. On evite aussi expres le celebre AKIAIOSFODNN7EXAMPLE
# de la doc AWS : la regle par defaut de gitleaks a une liste blanche sur tout ce
# qui se termine par "EXAMPLE", ce format ne serait donc jamais detecte.
fake_token="ghp_$(python3 -c 'import random, string; print("".join(random.choices(string.ascii_letters + string.digits, k=36)))')"
echo "GITHUB_TOKEN=$fake_token" > "$TMP_DIR/leak.env"

if gitleaks_output="$(MSYS_NO_PATHCONV=1 docker run --rm -v "$TMP_DIR:/scan" "$GITLEAKS_IMAGE" detect --source=/scan --no-git --no-banner -v 2>&1)"; then
  gitleaks_exit=0
else
  gitleaks_exit=$?
fi
proof_lines+=("gitleaks sur un faux token GitHub injecte (exit=$gitleaks_exit):"$'\n'"$gitleaks_output")

if [ "$gitleaks_exit" -eq 0 ]; then
  result="FAIL"
  proof_lines+=("ECHEC: gitleaks n'a rien detecte sur un secret connu (detection cassee)")
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
