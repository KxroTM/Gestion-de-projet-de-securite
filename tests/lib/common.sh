#!/usr/bin/env bash
# Helpers partages par les tests bash (tests/test_*.sh).
# A sourcer avec: source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPORTS_DIR="$PROJECT_ROOT/reports"
mkdir -p "$REPORTS_DIR"

cd "$PROJECT_ROOT"

# Execute une commande RCON sur le serveur mc via le rcon-cli embarque dans l'image.
rcon() {
  docker compose exec -T mc rcon-cli "$@"
}

# wait_healthy <container> [timeout_s=180]
# Positionne WAIT_HEALTHY_SECONDS et retourne 0 si "healthy" avant le timeout, 1 sinon.
wait_healthy() {
  local container="$1" timeout="${2:-180}" waited=0 status
  while true; do
    status="$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "missing")"
    if [ "$status" = "healthy" ]; then
      WAIT_HEALTHY_SECONDS=$waited
      return 0
    fi
    if [ "$waited" -ge "$timeout" ]; then
      WAIT_HEALTHY_SECONDS=$waited
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
}

# write_report <id> <requirement> <OK|FAIL> <duration_s> <proof>
# Ecrit reports/<id>.json : { id, requirement, result, duration_s, proof }
write_report() {
  local id="$1" requirement="$2" result="$3" duration="$4" proof="$5"
  python3 -c '
import json, sys
path, id_, requirement, result, duration, proof = sys.argv[1:7]
report = {
    "id": id_,
    "requirement": requirement,
    "result": result,
    "duration_s": float(duration),
    "proof": proof,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2, ensure_ascii=False)
' "$REPORTS_DIR/$id.json" "$id" "$requirement" "$result" "$duration" "$proof"
  echo "[$id] $result (${duration}s) -> reports/$id.json"
}
