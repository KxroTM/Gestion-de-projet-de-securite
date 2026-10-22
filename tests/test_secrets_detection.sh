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

# Faux token GitHub (regle "github-pat" de gitleaks). On evite expres le celebre
# AKIAIOSFODNN7EXAMPLE de la doc AWS : la regle par defaut de gitleaks a une liste
# blanche sur tout ce qui se termine par "EXAMPLE" pour eviter les faux positifs
# sur la documentation AWS, donc ce format ne serait jamais detecte.
cat > "$TMP_DIR/leak.env" <<'EOF'
GITHUB_TOKEN=ghp_WzFgxTkBE53S530nsjNeadM6IQWchvpik7Sl
EOF

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
